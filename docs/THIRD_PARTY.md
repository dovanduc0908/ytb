# Thành phần nguồn mở của bản Android độc lập

- [youtubedl-android 0.18.1](https://github.com/yausername/youtubedl-android): GPL-3.0; giấy phép đầy đủ tại `YOUTUBEDL_ANDROID_LICENSE.txt`. Gói Maven kèm Python và QuickJS chạy ngay trên Android.
- [yt-dlp 2026.10.21](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.21): file zip executable chính thức được đóng trong `apps/native/android/app/src/main/res/raw/ytdlp`; SHA-256 `b7af77f686e95f7845ce8d09d21957718febb8b48b30555adb9dd2292ad7bf14`, đã đối chiếu SHA2-256SUMS của cùng bản phát hành. Gói này có kèm bộ EJS.
- Flutter, AndroidX Media3 (gồm datasource-okhttp), OkHttp 4.12.0, shared_preferences: các phiên bản khóa trong `pubspec.lock` và Gradle.

Bản bàn giao bao gồm mã nguồn ứng dụng và các tệp build trong workspace. Khi phân phối tiếp, cần giữ thông báo giấy phép và đáp ứng các điều kiện phân phối mã nguồn của thành phần GPL. Không cần tải/cài thêm Python, QuickJS hay ứng dụng hỗ trợ. Việc truy cập YouTube vẫn tải dữ liệu và player JavaScript của YouTube; phiên bản bộ trích xuất được cập nhật cùng APK.
