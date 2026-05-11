import java.util.Properties
import java.io.FileInputStream

fun asBuildConfigString(value: String): String =
    "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""

fun readBuildSecret(name: String): String =
    providers.environmentVariable(name).orElse("").get().trim()

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") // For flutter_local_notifications // Workaround for: https://github.com/MaikuB/flutter_local_notifications/issues/2286
    implementation("androidx.core:core-ktx:1.17.0") // For Android Auto
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("com.alibaba.pdns:alidns-android-sdk:2.3.0")
    implementation("com.google.code.gson:gson:2.8.5")
    implementation("com.github.Tencent.soter:soter-wrapper:2.0.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}


// Workaround for https://pub.dev/packages/unifiedpush#the-build-fails-because-of-duplicate-classes
configurations.all {
    // Use the latest version published: https://central.sonatype.com/artifact/com.google.crypto.tink/tink-android
    val tink = "com.google.crypto.tink:tink-android:1.17.0"
    // You can also use the library declaration catalog
    // val tink = libs.google.tink
    resolutionStrategy {
        force(tink)
        dependencySubstitution {
            substitute(module("com.google.crypto.tink:tink")).using(module(tink))
        }
    }
}


android {
    namespace = "chat.fluffy.fluffychat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
       create("release") {
            keyAlias = "dummyAlias"
            keyPassword = "dummyPassword"
            storeFile = file("dummy.keystore")
            storePassword = "dummyStorePassword"
        }
    }

    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
        signingConfigs.getByName("release").apply {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    val unsignedRelease =
        providers.environmentVariable("FLUFFYCHAT_UNSIGNED_RELEASE")
            .orNull
            ?.equals("true", ignoreCase = true) == true
    val configuredAbiFilters =
        providers.environmentVariable("FLUFFYCHAT_ABI_FILTERS")
            .orNull
            ?.split(",")
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
    val aliyunHttpDnsAccountId = readBuildSecret("ALIYUN_HTTPDNS_ACCOUNT_ID")
    val aliyunHttpDnsAccessKeyId = readBuildSecret("ALIYUN_HTTPDNS_ACCESS_KEY_ID")
    val aliyunHttpDnsAccessKeySecret =
        readBuildSecret("ALIYUN_HTTPDNS_ACCESS_KEY_SECRET")
    val aliyunHttpDnsCredentialsConfigured =
        aliyunHttpDnsAccountId.isNotBlank() &&
            aliyunHttpDnsAccessKeyId.isNotBlank() &&
            aliyunHttpDnsAccessKeySecret.isNotBlank()

    defaultConfig {
        applicationId = "chat.fluffy.fluffychat"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField(
            "String",
            "ALIYUN_HTTPDNS_ACCOUNT_ID",
            asBuildConfigString(aliyunHttpDnsAccountId),
        )
        buildConfigField(
            "String",
            "ALIYUN_HTTPDNS_ACCESS_KEY_ID",
            asBuildConfigString(aliyunHttpDnsAccessKeyId),
        )
        buildConfigField(
            "String",
            "ALIYUN_HTTPDNS_ACCESS_KEY_SECRET",
            asBuildConfigString(aliyunHttpDnsAccessKeySecret),
        )
        buildConfigField(
            "boolean",
            "ALIYUN_HTTPDNS_CREDENTIALS_CONFIGURED",
            aliyunHttpDnsCredentialsConfigured.toString(),
        )
        ndk { // Workaround for https://github.com/flutter/flutter/issues/162153#issuecomment-2612443642
            val defaultAbiFilters = listOf("armeabi-v7a", "arm64-v8a", "x86_64", "x86")
            abiFilters += configuredAbiFilters ?: defaultAbiFilters
        }
    }

    buildTypes {
        release {
            if (!unsignedRelease) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
