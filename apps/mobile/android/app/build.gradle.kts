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

fun signingProperty(propertyName: String, environmentName: String): String? =
    providers.environmentVariable(environmentName).orNull
        ?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseSigningValues = mapOf(
    "keyAlias" to signingProperty("keyAlias", "ANDROID_RELEASE_KEY_ALIAS"),
    "keyPassword" to signingProperty("keyPassword", "ANDROID_RELEASE_KEY_PASSWORD"),
    "storeFile" to signingProperty("storeFile", "ANDROID_RELEASE_STORE_FILE"),
    "storePassword" to signingProperty("storePassword", "ANDROID_RELEASE_STORE_PASSWORD"),
)
val hasCompleteReleaseSigning = releaseSigningValues.values.all { it != null }

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
            signingConfig = signingConfigs.getByName("debug")
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

// Keep dev/local builds usable without production material, but make a direct
// Gradle/Flutter prod release invocation fail before packaging when it is absent.
gradle.taskGraph.whenReady {
    val buildsProdRelease = allTasks.any { task ->
        task.name.contains("ProdRelease", ignoreCase = true)
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
    androidTestUtil("androidx.test:orchestrator:1.5.1")
    androidTestUtil("androidx.test.services:test-services:1.5.0")
}
