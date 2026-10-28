plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    buildFeatures { resValues = true }
    namespace = "com.duchaik.ytb"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols.add("**/libpython.zip.so")
            // Flutter ships ARMv7, ARM64 and x86_64; never advertise unsupported x86.
            excludes.add("lib/x86/**")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.duchaik.ytb"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        if (project.findProperty("target-platform") == "android-arm64") {
            ndk { abiFilters.add("arm64-v8a") }
        }
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val updateProject = System.getenv("YTB_UPDATE_REPOSITORY") ?: "dovanduc0908/ytb"
        require(updateProject.matches(Regex("[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"))) { "Invalid update repository" }
        resValue("string", "update_release_api", "https://api.github.com/repos/$updateProject/releases/latest")
    }

    val keyPath = System.getenv("YTB_ANDROID_KEYSTORE")
    val releaseKeyPassword = System.getenv("YTB_ANDROID_KEY_PASSWORD")
    val releaseStorePassword = System.getenv("YTB_ANDROID_STORE_PASSWORD")
    val releaseKeyAlias = System.getenv("YTB_ANDROID_KEY_ALIAS")
    val hasReleaseKey = !keyPath.isNullOrBlank() && !releaseKeyPassword.isNullOrBlank() && !releaseStorePassword.isNullOrBlank() && !releaseKeyAlias.isNullOrBlank()
    if (listOf(keyPath, releaseKeyPassword, releaseStorePassword, releaseKeyAlias).any { !it.isNullOrBlank() }) {
        require(hasReleaseKey) { "Set all YTB_ANDROID signing variables together" }
    }
    val configuredRelease = if (hasReleaseKey) signingConfigs.create("configuredRelease") {
        storeFile = file(keyPath!!)
        this.storePassword = releaseStorePassword
        this.keyAlias = releaseKeyAlias
        this.keyPassword = releaseKeyPassword
    } else null
    buildTypes {
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = configuredRelease ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-dash:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("androidx.media3:media3-ui:1.11.1")
    implementation("androidx.media3:media3-datasource-okhttp:1.11.1")
    implementation("androidx.media3:media3-session:1.11.1")
}
