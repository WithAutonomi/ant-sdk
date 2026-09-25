plugins {
    kotlin("jvm")
    application
}

dependencies {
    implementation(project(":lib"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("org.web3j:core:4.12.3")

    testImplementation(kotlin("test"))
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}

tasks.test {
    useJUnitPlatform()
}

application {
    mainClass.set("com.autonomi.examples.MainKt")
}

kotlin {
    jvmToolchain(17)
}
