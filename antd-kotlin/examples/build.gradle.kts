plugins {
    kotlin("jvm")
    application
}

dependencies {
    implementation(project(":lib"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
}

application {
    mainClass.set("com.autonomi.examples.MainKt")
}

kotlin {
    jvmToolchain(17)
}
