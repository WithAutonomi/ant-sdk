plugins {
    id("com.android.library") version "8.5.2"
    id("org.jetbrains.kotlin.android") version "1.9.25"
    id("maven-publish")
}

// Published coordinates: com.autonomi:ant-android:<version>. Version defaults to
// the current SDK release but can be overridden for automation:
//   gradle publish -PantAndroidVersion=0.0.4
group = "com.autonomi"
version = (findProperty("antAndroidVersion") ?: "0.0.3").toString()

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

    // Required for maven-publish's `components["release"]` to exist (AGP 8.x).
    publishing {
        singleVariant("release")
    }
}

// Publish com.autonomi:ant-android as an AAR + POM into a local Maven layout
// (build/maven-repo/), which is then committed to the ant-maven repo and served
// over GitHub Pages. `from(components["release"])` carries the JNA + coroutines
// `api` deps into the generated POM so consumers resolve them transitively.
afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                artifactId = "ant-android"
            }
        }
        repositories {
            maven {
                name = "pages"
                url = uri(layout.buildDirectory.dir("maven-repo"))
            }
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
