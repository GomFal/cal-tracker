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

fun signingProperty(name: String): String =
    keystoreProperties.getProperty(name)
        ?: throw GradleException("Missing Android signing property: $name")

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

    flavorDimensions += "env"

    productFlavors {
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "BetterCalories")
        }
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "dev:BetterCalories")
        }
        create("local") {
            dimension = "env"
            applicationIdSuffix = ".dev.local"
            resValue("string", "app_name", "local:BetterCalories")
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = signingProperty("keyAlias")
                keyPassword = signingProperty("keyPassword")
                storeFile = file(signingProperty("storeFile"))
                storePassword = signingProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
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
