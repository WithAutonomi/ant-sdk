plugins {
    java
    application
}

repositories {
    mavenCentral()
}

dependencies {
    implementation(project(":"))
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}

// Pick which example to run with:
// gradle :examples:run -PmainClass=com.autonomi.examples.Example02PublicData
application {
    mainClass.set(
        (project.findProperty("mainClass") as String?)
            ?: "com.autonomi.examples.Example02PublicData"
    )
}
