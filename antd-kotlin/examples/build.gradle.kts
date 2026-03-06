plugins {
    kotlin("jvm")
    application
}

dependencies {
    implementation(project(":lib"))
}

application {
    mainClass.set("com.autonomi.examples.MainKt")
}

kotlin {
    jvmToolchain(17)
}
