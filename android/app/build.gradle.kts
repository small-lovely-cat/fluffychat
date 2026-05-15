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

/**
 * 清理 Flutter 生成的插件注册文件中无法编译的无效插件注册代码。
 *
 * @param projectDir 当前 Android app 模块目录
 * @return 无返回值
 */
fun sanitizeGeneratedPluginRegistrant(projectDir: File) {
    val registrantFile =
        projectDir.resolve("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
    if (!registrantFile.exists()) {
        return
    }

    val originalContent = registrantFile.readText()
    val invalidPluginPatterns =
        listOf(
            Regex(
                """\s*try\s*\{\s*flutterEngine\.getPlugins\(\)\.add\(new net\.jonhanson\.flutter_native_splash\.FlutterNativeSplashPlugin\(\)\);\s*}\s*catch\s*\(Exception e\)\s*\{\s*Log\.e\(TAG, "Error registering plugin flutter_native_splash, net\.jonhanson\.flutter_native_splash\.FlutterNativeSplashPlugin", e\);\s*}\s*""",
            ),
            Regex(
                """\s*try\s*\{\s*flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\s*}\s*catch\s*\(Exception e\)\s*\{\s*Log\.e\(TAG, "Error registering plugin integration_test, dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin", e\);\s*}\s*""",
            ),
        )
    val sanitizedContent =
        invalidPluginPatterns.fold(originalContent) { currentContent, invalidPattern ->
            currentContent.replace(invalidPattern, "\n")
        }

    if (originalContent != sanitizedContent) {
        registrantFile.writeText(sanitizedContent)
    }
}

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
    implementation("androidx.room:room-rxjava2:2.2.0")
    implementation("com.alibaba.pdns:alidns-android-sdk:2.3.0")
    implementation("com.bytedance.frameworks.baselib:httpdns:1.0.23")
    implementation("com.google.code.gson:gson:2.8.5")
    implementation("com.github.Tencent.soter:soter-wrapper:2.0.7")
    implementation("com.tencent:mmkv:2.4.0")
    implementation("io.github.dnspod:httpdns-sdk:4.4.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}

tasks.register("sanitizeGeneratedPluginRegistrant") {
    doLast {
        sanitizeGeneratedPluginRegistrant(projectDir)
    }
}

tasks.named("preBuild") {
    dependsOn("sanitizeGeneratedPluginRegistrant")
}

tasks.matching {
    it.name == "compileReleaseJavaWithJavac" || it.name == "compileDebugJavaWithJavac"
}.configureEach {
    dependsOn("sanitizeGeneratedPluginRegistrant")
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
    val veHttpDnsAccountId =
        readBuildSecret("VE_HTTPDNS_ACCOUNT_ID", localBuildProperties)
    val veHttpDnsSecretKey =
        readBuildSecret("VE_HTTPDNS_SECRET_KEY", localBuildProperties)
    val veHttpDnsAppId =
        readBuildSecret("VE_HTTPDNS_APP_ID", localBuildProperties)
    val veHttpDnsDohDomains =
        readBuildSecret("VE_HTTPDNS_DOH_DOMAINS", localBuildProperties)
    val veHttpDnsUseDoh =
        readBuildSecret("VE_HTTPDNS_USE_DOH", localBuildProperties)
            .equals("true", ignoreCase = true)
    val veHttpDnsCredentialsConfigured =
        veHttpDnsAccountId.isNotBlank() &&
            veHttpDnsSecretKey.isNotBlank()
    val tencentHttpDnsId =
        readBuildSecret("TENCENT_HTTPDNS_ID", localBuildProperties)
    val tencentHttpDnsKey =
        readBuildSecret("TENCENT_HTTPDNS_KEY", localBuildProperties)
    val tencentHttpDnsCredentialsConfigured =
        tencentHttpDnsId.isNotBlank() &&
            tencentHttpDnsKey.isNotBlank()

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
        buildConfigField(
            "String",
            "VE_HTTPDNS_ACCOUNT_ID",
            asBuildConfigString(veHttpDnsAccountId),
        )
        buildConfigField(
            "String",
            "VE_HTTPDNS_SECRET_KEY",
            asBuildConfigString(veHttpDnsSecretKey),
        )
        buildConfigField(
            "String",
            "VE_HTTPDNS_APP_ID",
            asBuildConfigString(veHttpDnsAppId),
        )
        buildConfigField(
            "String",
            "VE_HTTPDNS_DOH_DOMAINS",
            asBuildConfigString(veHttpDnsDohDomains),
        )
        buildConfigField(
            "boolean",
            "VE_HTTPDNS_USE_DOH",
            veHttpDnsUseDoh.toString(),
        )
        buildConfigField(
            "boolean",
            "VE_HTTPDNS_CREDENTIALS_CONFIGURED",
            veHttpDnsCredentialsConfigured.toString(),
        )
        buildConfigField(
            "String",
            "TENCENT_HTTPDNS_ID",
            asBuildConfigString(tencentHttpDnsId),
        )
        buildConfigField(
            "String",
            "TENCENT_HTTPDNS_KEY",
            asBuildConfigString(tencentHttpDnsKey),
        )
        buildConfigField(
            "boolean",
            "TENCENT_HTTPDNS_CREDENTIALS_CONFIGURED",
            tencentHttpDnsCredentialsConfigured.toString(),
        )
        ndk { // Workaround for https://github.com/flutter/flutter/issues/162153#issuecomment-2612443642
            // WCDB Android 迁移当前仅保留 arm64-v8a，按需求不再兼容其他 ABI。
            val defaultAbiFilters = listOf("arm64-v8a")
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
