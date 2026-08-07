import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "org.tylog.tylog"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.tylog.tylog"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    sourceSets {
        getByName("androidTest") {
            java.srcDirs("src/androidTest/kotlin")
        }
        getByName("debug") {
            java.srcDirs("src/debug/kotlin")
        }
    }

    if (keystorePropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        // Sign profile builds with the release key so a `--profile` build installs
        // over other locally-signed builds (same signature) without an uninstall
        // that would wipe the vault registry — enables on-device profiling.
        // `profile` is created by the Flutter Gradle plugin (no static accessor),
        // so resolve it by name rather than with a `profile { }` block.
        if (keystorePropertiesFile.exists()) {
            getByName("profile") {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    implementation("androidx.annotation:annotation:1.8.2")
    // SafBridge.writeAtomic is the one path that can lose a note, and nothing
    // in the Dart suite can exercise it: the "SAF" fake there is an empty
    // LocalVaultStorage subclass, so it uses POSIX rename and overwrites
    // silently. These run it against a provider that de-duplicates like AOSP.
    // Runner only, pinned to what integration_test resolves to strictly.
    // Deliberately not androidx.test.ext:junit — it drags in test activities
    // declared without android:exported, which targetSdk 36 rejects outright.
    androidTestImplementation("androidx.test:runner:1.3.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
