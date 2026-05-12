import java.util.Properties
import java.io.FileInputStream

/**
 * 将普通字符串转成可写入 BuildConfig 的 Java 字符串字面量。
 *
 * @param value 需要写入 BuildConfig 的原始字符串
 * @return 转义后的 Java 字符串字面量
 */
fun asBuildConfigString(value: String): String =
    "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""

/**
 * 读取本地构建使用的敏感参数。
 *
 * 优先读取系统环境变量，便于 CI 注入；若环境变量为空，则回退到
 * android/local.properties，便于 Android Studio 本地直接打包。
 *
 * @param name 参数名，同时作为环境变量名和 local.properties key
 * @param localProperties 当前 Android 工程的 local.properties
 * @return 读取到的参数值；未配置时返回空字符串
 */
fun readBuildSecret(name: String, localProperties: Properties): String =
    providers.environmentVariable(name)
        .orNull
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
        ?: localProperties.getProperty(name)?.trim().orEmpty()

val localBuildProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use(::load)
    }
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
    val aliyunHttpDnsAccountId =
        readBuildSecret("ALIYUN_HTTPDNS_ACCOUNT_ID", localBuildProperties)
    val aliyunHttpDnsAccessKeyId =
        readBuildSecret("ALIYUN_HTTPDNS_ACCESS_KEY_ID", localBuildProperties)
    val aliyunHttpDnsAccessKeySecret =
        readBuildSecret("ALIYUN_HTTPDNS_ACCESS_KEY_SECRET", localBuildProperties)
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
