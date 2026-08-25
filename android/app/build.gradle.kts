import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase (notifications push + suivi des crashs) — actifs UNIQUEMENT si
// google-services.json est present.
//
// Les plugins google-services/crashlytics font echouer le build quand le
// fichier manque. En conditionnant leur application, le projet reste
// compilable sans Firebase (push et Crashlytics natifs alors inactifs, voir
// push_service.dart et main.dart) et se cable tout seul des que le fichier
// est depose dans android/app/.
//
// Ou l'obtenir : console Firebase > Parametres du projet > Vos applications >
// Android > google-services.json. Le nom de package doit correspondre a
// applicationId ci-dessous : com.widjila.suivichantier
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
} else {
    logger.warn("[firebase] google-services.json absent — notifications push et Crashlytics natifs desactives")
}

// Signature de release — lit android/key.properties (JAMAIS committe, voir
// .gitignore).
//
// IMPORTANT : ce fichier ne peut pas faire ECHOUER `flutter run`/`flutter
// build ... --debug` quand key.properties est absent — les blocs
// `buildTypes { release { ... } }` sont evalues par Gradle a la
// CONFIGURATION du projet pour TOUTES les variantes, meme celles qu'on ne
// construit pas (piege classique de l'AGP : un throw ici casserait aussi le
// dev quotidien en debug). Le seul filet de securite fiable est donc
// l'avertissement ci-dessous, imprime a CHAQUE invocation de Gradle tant que
// key.properties manque — ne jamais le rater avant un `--release`.
//
// Pour generer un keystore de release et ce fichier : voir le guide
// PRODUCTION_READINESS.md a la racine du depot mobile.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
} else {
    logger.warn(
        "[signing] ############################################################\n" +
            "[signing] android/key.properties ABSENT.\n" +
            "[signing] Un `assembleRelease`/`bundleRelease` maintenant produirait un\n" +
            "[signing] artefact signe avec la cle de DEBUG — NON PUBLIABLE tel quel.\n" +
            "[signing] Voir PRODUCTION_READINESS.md pour generer un vrai keystore.\n" +
            "[signing] ############################################################"
    )
}

android {
    namespace = "com.widjila.suivichantier"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // `flutter_local_notifications` (18.x) compile contre des API de date
        // du JDK absentes des anciens Android : sans desugaring de la
        // bibliotheque de base, `CheckAarMetadata` refuse le build release.
        // Voir https://developer.android.com/studio/write/java8-support
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.widjila.suivichantier"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                storeFile = storeFilePath?.let { rootProject.file(it) }
            }
        }
    }

    buildTypes {
        release {
            // Cle de release si android/key.properties existe (voir plus
            // haut) ; a defaut, repli sur la cle de debug — UNIQUEMENT pour
            // ne pas casser un `flutter run --release` de developpement.
            // L'avertissement ci-dessus rappelle que ce repli n'est pas
            // publiable. Voir PRODUCTION_READINESS.md.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Obfuscation + suppression des ressources inutilisees — AAB plus
            // leger, code Dart/Kotlin/Java non lisible tel quel dans le
            // binaire livre. Regles dans proguard-rules.pro (Flutter, Dio,
            // Firebase, flutter_local_notifications).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // Fournit l'implementation des API desugarees activees ci-dessus
    // (`isCoreLibraryDesugaringEnabled`). Version minimale exigee par
    // flutter_local_notifications 18.x : 2.0.4.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
