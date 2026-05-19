plugins {
    kotlin("jvm")
    application
}

dependencies {
    implementation(project(":lib"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("org.web3j:core:4.12.3")
}

application {
    mainClass.set("com.autonomi.examples.MainKt")
}

kotlin {
    jvmToolchain(17)
}
