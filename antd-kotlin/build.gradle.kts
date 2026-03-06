plugins {
    kotlin("jvm") version "1.9.24" apply false
    id("com.google.protobuf") version "0.9.4" apply false
}

allprojects {
    group = "com.autonomi"
    version = "0.1.0"

    repositories {
        mavenCentral()
    }
}
