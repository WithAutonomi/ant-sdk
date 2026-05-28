plugins {
    id("com.android.library") version "8.5.2"
    id("org.jetbrains.kotlin.android") version "1.9.25"
}

android {
    namespace = "com.autonomi.antffi"
    compileSdk = 34

    defaultConfig {
        // Android 7.0 (API 24) baseline — covers ~98% of devices and keeps us
        // clear of older Android versions that have JNI quirks with QUIC/UDP.
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    sourceSets {
        getByName("main") {
            // .so files are dropped here by build-android.sh (one per ABI under
            // jniLibs/<abi>/libant_ffi.so) before invoking `gradle assembleRelease`.
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
}

dependencies {
    // JNA — uniffi-generated Kotlin uses JNA to call into libant_ffi.so.
    // The `:android-aarch64` etc. variants aren't needed because we ship
    // the JNI libs directly via `jniLibs.srcDirs` above; consumers only
    // need the JVM-side JNA jar.
    api("net.java.dev.jna:jna:5.14.0@aar")
    // Required for the `suspend fn` wrappers uniffi generates for async Rust.
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
}
