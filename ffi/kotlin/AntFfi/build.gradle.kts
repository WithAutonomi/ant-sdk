plugins {
    kotlin("jvm") version "1.9.24"
}

group = "com.autonomi"
version = "0.1.0"

repositories {
    mavenCentral()
}

dependencies {
    // JNA for UniFFI native bindings
    implementation("net.java.dev.jna:jna:5.14.0")

    // Kotlin coroutines (for async UniFFI bindings)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")

    testImplementation(kotlin("test"))
}

kotlin {
    jvmToolchain(17)
}

// Include auto-generated UniFFI bindings
sourceSets {
    main {
        kotlin.srcDirs("src/main/kotlin", "Generated")
    }
}

tasks.test {
    useJUnitPlatform()
}
