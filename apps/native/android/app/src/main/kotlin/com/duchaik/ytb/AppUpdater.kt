package com.duchaik.ytb

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Downloads only explicitly selected GitHub releases and checks the APK identity before install. */
class AppUpdater(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS).build()
    private val releaseApi = activity.getString(com.duchaik.ytb.R.string.update_release_api)
    @Volatile private var busy = false
    private var verified: File? = null
    private fun version(info: android.content.pm.PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
    @Suppress("DEPRECATION") private fun signatures(info: android.content.pm.PackageInfo): Set<String> =
        (if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures)?.map { it.toCharsString() }?.toSet() ?: emptySet()
    private fun validHttps(url: String): Boolean = Uri.parse(url).let { it.scheme == "https" && !it.host.isNullOrBlank() }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "install") {
            val file = verified
            if (file == null || !file.isFile) { result.error("NO_APK", "Hãy kiểm tra cập nhật lại", null); return }
            if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                result.success("permission"); return
            }
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
            activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
            result.success("installer"); return
        }
        if (call.method != "check") { result.notImplemented(); return }
        if (busy) { result.error("BUSY", "Đang kiểm tra cập nhật", null); return }
        busy = true; verified = null
        executor.execute {
            val target = File(activity.cacheDir, "updates/update.apk")
            try {
                val release = client.newCall(Request.Builder().url(releaseApi).build()).execute().use { response ->
                    if (response.code == 404) error("Không tìm thấy bản cập nhật công khai trên GitHub. Hãy kiểm tra nơi phát hành.")
                    if (!response.isSuccessful) error("GitHub trả lỗi ${response.code}")
                    JSONObject(response.body?.string() ?: error("GitHub không trả dữ liệu"))
                }
                @Suppress("DEPRECATION") val currentInfo = activity.packageManager.getPackageInfo(activity.packageName, 0)
                val tagCode = Regex("^build-(\\d+)$").matchEntire(release.optString("tag_name"))?.groupValues?.get(1)?.toLongOrNull()
                if (tagCode != null && tagCode <= version(currentInfo)) {
                    val info = mapOf("available" to false, "current" to (currentInfo.versionName ?: ""), "currentCode" to version(currentInfo))
                    main.post { busy = false; result.success(info) }; return@execute
                }
                val links = release.optJSONArray("assets") ?: error("Release chưa có tệp APK")
                val candidates = (0 until links.length()).mapNotNull { links.optJSONObject(it) }.filter {
                    it.optString("name").endsWith(".apk", true) || Uri.parse(it.optString("browser_download_url")).path?.endsWith(".apk", true) == true
                }
                require(candidates.size == 1) { "Release cần đúng một tệp APK" }
                val url = candidates.single().optString("browser_download_url")
                require(validHttps(url)) { "Địa chỉ APK phải dùng HTTPS" }
                target.parentFile?.mkdirs(); target.delete()
                client.newCall(Request.Builder().url(url).build()).execute().use { response ->
                    require(response.isSuccessful && validHttps(response.request.url.toString())) { "Không tải được APK qua HTTPS" }
                    val body = response.body ?: error("APK rỗng")
                    require(body.contentLength() <= 256L * 1024 * 1024) { "APK vượt giới hạn 256 MiB" }
                    body.byteStream().use { input -> target.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024); var total = 0L
                        while (true) { val count = input.read(buffer); if (count < 0) break; total += count; require(total <= 256L * 1024 * 1024) { "APK vượt giới hạn 256 MiB" }; output.write(buffer, 0, count) }
                    } }
                }
                val pm = activity.packageManager
                val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
                @Suppress("DEPRECATION") val archive = pm.getPackageArchiveInfo(target.absolutePath, flags) ?: error("Tệp không phải APK hợp lệ")
                @Suppress("DEPRECATION") val installed = pm.getPackageInfo(activity.packageName, flags)
                require(archive.packageName == activity.packageName) { "APK không thuộc ứng dụng này" }
                val expected = signatures(installed); require(expected.isNotEmpty() && signatures(archive) == expected) { "Chữ ký APK không khớp bản đang cài" }
                val newer = version(archive) > version(installed)
                if (newer) verified = target else target.delete()
                val info = mapOf("available" to newer, "version" to (archive.versionName ?: ""), "current" to (installed.versionName ?: ""), "code" to version(archive), "currentCode" to version(installed))
                main.post { busy = false; result.success(info) }
            } catch (e: Exception) {
                target.delete(); main.post { busy = false; result.error("UPDATE", e.message ?: "Không kiểm tra được cập nhật", null) }
            }
        }
    }
}
