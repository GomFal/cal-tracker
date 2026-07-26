import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun environmentSigningProperty(environmentName: String): String? =
    providers.environmentVariable(environmentName).orNull
        ?.takeIf { it.isNotBlank() }

fun signingProperty(propertyName: String, environmentName: String): String? =
    environmentSigningProperty(environmentName)
        ?: keystoreProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseSigningValues = mapOf(
    "keyAlias" to signingProperty("keyAlias", "ANDROID_RELEASE_KEY_ALIAS"),
    "keyPassword" to signingProperty("keyPassword", "ANDROID_RELEASE_KEY_PASSWORD"),
    "storeFile" to signingProperty("storeFile", "ANDROID_RELEASE_STORE_FILE"),
    "storePassword" to signingProperty("storePassword", "ANDROID_RELEASE_STORE_PASSWORD"),
)
val hasCompleteReleaseSigning = releaseSigningValues.values.all { it != null }
val devSigningValues = mapOf(
    "keyAlias" to environmentSigningProperty("ANDROID_DEV_KEY_ALIAS"),
    "keyPassword" to environmentSigningProperty("ANDROID_DEV_KEY_PASSWORD"),
    "storeFile" to environmentSigningProperty("ANDROID_DEV_STORE_FILE"),
    "storePassword" to environmentSigningProperty("ANDROID_DEV_STORE_PASSWORD"),
)
val hasCompleteDevSigning = devSigningValues.values.all { it != null }

android {
    namespace = "com.example.cal_tracker_mobile"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "app.bettercalories"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
    }

    testOptions {
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
    }

    signingConfigs {
        if (hasCompleteDevSigning) {
            create("devRelease") {
                keyAlias = devSigningValues.getValue("keyAlias")
                keyPassword = devSigningValues.getValue("keyPassword")
                storeFile = file(devSigningValues.getValue("storeFile")!!)
                storePassword = devSigningValues.getValue("storePassword")
            }
        }
        if (hasCompleteReleaseSigning) {
            create("release") {
                keyAlias = releaseSigningValues.getValue("keyAlias")
                keyPassword = releaseSigningValues.getValue("keyPassword")
                storeFile = file(releaseSigningValues.getValue("storeFile")!!)
                storePassword = releaseSigningValues.getValue("storePassword")
            }
        }
    }

    flavorDimensions += "env"

    productFlavors {
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "BetterCalories")
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "dev:BetterCalories")
            signingConfigs.findByName("devRelease")?.let { signingConfig = it }
        }
        create("local") {
            dimension = "env"
            applicationIdSuffix = ".dev.local"
            resValue("string", "app_name", "local:BetterCalories")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// Keep debug builds usable without publication material, but make direct
// Gradle/Flutter dev/prod release invocations fail before packaging when their
// channel-specific signing identity is absent.
gradle.taskGraph.whenReady {
    val buildsDevRelease = allTasks.any { task ->
        task.name.contains("DevRelease", ignoreCase = true)
    }
    val buildsProdRelease = allTasks.any { task ->
        task.name.contains("ProdRelease", ignoreCase = true)
    }
    if (buildsDevRelease && !hasCompleteDevSigning) {
        throw GradleException(
            "Development release signing is incomplete. Configure the " +
                "ANDROID_DEV_* environment variables.",
        )
    }
    if (buildsProdRelease && !hasCompleteReleaseSigning) {
        throw GradleException(
            "Production release signing is incomplete. Configure key.properties " +
                "or the ANDROID_RELEASE_* environment variables.",
        )
    }
}

androidComponents {
    beforeVariants(selector().withBuildType("release").withFlavor("env" to "local")) { variant ->
        variant.enable = false
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.18.0")
    androidTestUtil("androidx.test:orchestrator:1.5.1")
    androidTestUtil("androidx.test.services:test-services:1.5.0")
}

fun decodedDartDefine(name: String): String? {
    val encodedDefines = project.findProperty("dart-defines") as? String
        ?: return null
    return encodedDefines
        .split(',')
        .mapNotNull { encoded ->
            runCatching {
                String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
            }.getOrNull()
        }
        .mapNotNull { define ->
            val separator = define.indexOf('=')
            if (separator <= 0) null
            else define.substring(0, separator) to define.substring(separator + 1)
        }
        .lastOrNull { (key, _) -> key == name }
        ?.second
}

fun registerReleaseApiValidationTask(
    taskName: String,
    releaseFlavor: String,
) = tasks.register(taskName) {
    group = "verification"
    description = "Validates API_BASE_URL for the $releaseFlavor release."
    doLast {
        val validator = rootProject.file(
            "../../../scripts/mobile/validate-api-base-url.sh",
        )
        val apiBaseUrl = decodedDartDefine("API_BASE_URL").orEmpty()
        val process = ProcessBuilder(
            "bash",
            validator.absolutePath,
            releaseFlavor,
            apiBaseUrl,
            "release",
        )
            .inheritIO()
            .start()
        if (process.waitFor() != 0) {
            throw GradleException(
                "Invalid API_BASE_URL for $releaseFlavor release build.",
            )
        }
    }
}

// Defense in depth for direct Flutter/Gradle release builds that bypass the
// repository build script. These tasks have no outputs, so validation also
// runs when Flutter's compile task is otherwise up-to-date.
val validateDevReleaseApiBaseUrl = registerReleaseApiValidationTask(
    "validateDevReleaseApiBaseUrl",
    "dev",
)
val validateProdReleaseApiBaseUrl = registerReleaseApiValidationTask(
    "validateProdReleaseApiBaseUrl",
    "prod",
)

tasks.configureEach {
    when (name) {
        "compileFlutterBuildDevRelease" -> dependsOn(validateDevReleaseApiBaseUrl)
        "compileFlutterBuildProdRelease" -> dependsOn(validateProdReleaseApiBaseUrl)
    }
}
