plugins {
    kotlin("jvm")
    kotlin("plugin.serialization") version "1.9.24"
    id("com.google.protobuf")
}

dependencies {
    // Kotlin coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")

    // JSON serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")

    // HTTP client (OkHttp)
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // gRPC
    implementation("io.grpc:grpc-kotlin-stub:1.4.1")
    implementation("io.grpc:grpc-protobuf:1.85.1")
    implementation("io.grpc:grpc-stub:1.85.1") // generated stubs need grpc-stub to match protoc-gen-grpc-java; grpc-kotlin-stub alone pulls an older one
    implementation("io.grpc:grpc-netty-shaded:1.85.1")
    implementation("com.google.protobuf:protobuf-kotlin:4.28.3")

    // grpc-java 1.85.1 (the latest release) still pulls guava 33.6.0-android,
    // which is affected by GHSA-xxph-c9ww-hj94 (fixed in 33.7.2). A constraint
    // raises only the floor, so it also reaches consumers of the published
    // artifact (Gradle module metadata). Drop it once grpc-java depends on
    // guava >= 33.7.2.
    constraints {
        implementation("com.google.guava:guava:33.7.2-android") {
            because("GHSA-xxph-c9ww-hj94: guava <= 33.7.1 unbounded allocation on deserialization")
        }
    }

    // Testing
    testImplementation(kotlin("test"))
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("io.grpc:grpc-inprocess:1.85.1")
    testImplementation("io.grpc:grpc-testing:1.85.1")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

protobuf {
    protoc {
        artifact = "com.google.protobuf:protoc:4.28.3"
    }
    plugins {
        create("grpc") {
            artifact = "io.grpc:protoc-gen-grpc-java:1.85.1"
        }
        create("grpckt") {
            artifact = "io.grpc:protoc-gen-grpc-kotlin:1.4.1:jdk8@jar"
        }
    }
    generateProtoTasks {
        all().forEach {
            it.plugins {
                create("grpc")
                create("grpckt")
            }
            it.builtins {
                create("kotlin")
            }
        }
    }
}

tasks.test {
    useJUnitPlatform()
}

kotlin {
    jvmToolchain(17)
}

// Copy proto files from antd
tasks.register<Copy>("copyProtos") {
    from("../../antd/proto/antd/v1")
    into("src/main/proto/antd/v1")
    include("*.proto")
}

tasks.named("processResources") {
    dependsOn("copyProtos")
}

// Ensure proto files are copied before protobuf generation
afterEvaluate {
    tasks.matching { it.name.startsWith("generateProto") }.configureEach {
        dependsOn("copyProtos")
    }
}
