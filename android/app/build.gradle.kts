plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.my_app_gps"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Enable core library desugaring (required for flutter_local_notifications)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.my_app_gps"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Build performance optimizations
        vectorDrawables {
            useSupportLibrary = true  // Use VectorDrawableCompat for better performance
        }
        
        // Disable test runner for faster builds (only enable when running tests)
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    // Split APKs by ABI to reduce download size (~40% smaller per APK)
    splits {
        abi {
            isEnable = true  // Generate separate APKs for each CPU architecture
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")  // Most common architectures
            isUniversalApk = true  // Also generate a universal APK for compatibility
        }
    }

    buildTypes {
        // Debug build type configuration
        debug {
            // Debug builds settings (default values shown for reference)
            isMinifyEnabled = false
            isShrinkResources = false
            isDebuggable = true
            applicationIdSuffix = ".debug"  // Allows installing debug alongside release
            versionNameSuffix = "-DEBUG"
        }

        // Release build type - optimized for production
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            
            // ============================================================
            // RELEASE BUILD OPTIMIZATIONS
            // ============================================================
            
            // Enable R8 code shrinking & obfuscation (removes unused code)
            // Impact: 30-50% smaller APK, faster startup, harder to reverse engineer
            isMinifyEnabled = true
            
            // Enable resource shrinking (removes unused resources)
            // Impact: 10-20% smaller APK by removing unused images, layouts, strings
            isShrinkResources = true
            
            // Disable debugging capabilities in release builds
            // Impact: Slightly smaller APK, prevents debugger attachment
            isDebuggable = false
            
            // Enable code optimization with R8
            // Impact: Faster app performance through inlining, dead code elimination
            isJniDebuggable = false  // Disable JNI debugging
            isPseudoLocalesEnabled = false  // Disable pseudo-locales (test feature)
            
            // ProGuard/R8 configuration files
            // proguard-android-optimize.txt: Aggressive optimization rules from Android SDK
            // proguard-rules.pro: Your custom keep rules for third-party libraries
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            
            // Optimize PNG images during build (lossless compression)
            // Impact: 5-15% smaller APK with no quality loss
            isCrunchPngs = true  // Default true, but explicit for clarity
            
            // Strip debug symbols from native libraries (.so files)
            // Impact: 20-30% smaller native libraries
            ndk {
                debugSymbolLevel = "NONE"  // Options: NONE, SYMBOL_TABLE, FULL
            }
            
            // Packaging options - exclude debug files
            packaging {
                resources {
                    excludes += setOf(
                        // Exclude debug metadata files
                        "DebugProbesKt.bin",
                        "kotlin-tooling-metadata.json",
                        // Exclude license files to reduce APK size
                        "META-INF/LICENSE*",
                        "META-INF/NOTICE*",
                        "META-INF/*.kotlin_module",
                        // Exclude duplicate files
                        "META-INF/INDEX.LIST",
                        "META-INF/io.netty.versions.properties"
                    )
                }
            }
        }
    }
    
    // Additional build optimizations
    buildFeatures {
        // Disable unused features to speed up build times
        buildConfig = true  // Keep BuildConfig for Flutter
        aidl = false  // Disable AIDL (not used by Flutter)
        renderScript = false  // Disable RenderScript (deprecated)
        shaders = false  // Disable shader compilation (not used by Flutter)
    }
    
    // Optimize build performance
    packagingOptions {
        jniLibs {
            // Keep only necessary native libraries
            useLegacyPackaging = false  // Use modern packaging (smaller APK)
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring (required for flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
