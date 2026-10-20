import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.psyche.kelivo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.buildx.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Flutter controls APK ABI filtering, including --split-per-abi.
        externalNativeBuild {
            cmake {
                abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
        unitTests.isIncludeAndroidResources = true
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(keystorePropertiesFile.inputStream())
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                throw GradleException(
                    "Missing android/key.properties. Release builds must be signed " +
                        "with the external Build X keystore.",
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

// Flutter generates GeneratedPluginRegistrant.java with dev-only plugins
// (integration_test, flutter_native_splash). Those plugins are intentionally
// absent from the release compile classpath. Strip their registrations for
// release, and restore them for debug/integration-test builds.
val devPluginRegistrant = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
val devPluginBackup = layout.buildDirectory.file("dev-plugin-registrant.java").get().asFile

fun stripDevPluginRegistrars() {
    if (!devPluginRegistrant.exists()) return
    val text = devPluginRegistrant.readText()
    if (!text.contains("flutter_native_splash") && !text.contains("integration_test")) {
        return
    }
    devPluginBackup.parentFile.mkdirs()
    devPluginBackup.writeText(text)
    val lines = text.lines().toMutableList()
    val markers = listOf(
        "new net.jonhanson.flutter_native_splash.",
        "new dev.flutter.plugins.integration_test.",
    )
    var i = 0
    while (i < lines.size) {
        if (markers.any { lines[i].contains(it) }) {
            var start = i
            while (start >= 0 && lines[start].trim() != "try {") start--
            var end = i
            while (end < lines.size && lines[end].trim() != "}") end++
            if (start >= 0 && end < lines.size) {
                lines.subList(start, end + 1).clear()
                i = start
                continue
            }
        }
        i++
    }
    devPluginRegistrant.writeText(lines.joinToString("\n"))
}

fun restoreDevPluginRegistrars() {
    if (devPluginRegistrant.exists() && devPluginBackup.exists()) {
        devPluginRegistrant.writeText(devPluginBackup.readText())
    }
}

tasks.matching { it.name == "compileReleaseJavaWithJavac" }.configureEach {
    doFirst { stripDevPluginRegistrars() }
}

tasks.matching { it.name == "compileDebugJavaWithJavac" }.configureEach {
    doFirst { restoreDevPluginRegistrars() }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.browser:browser:1.9.0")
    implementation("org.tukaani:xz:1.10")
    // Required for core library desugaring (used by flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
}
