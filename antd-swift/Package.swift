// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AntdSdk",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "AntdSdk", targets: ["AntdSdk"]),
        .executable(name: "AntdExamples", targets: ["AntdExamples"]),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "1.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .target(
            name: "AntdSdk",
            dependencies: [
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .executableTarget(
            name: "AntdExamples",
            dependencies: ["AntdSdk"]
        ),
        .testTarget(
            name: "AntdSdkTests",
            dependencies: ["AntdSdk"]
        ),
    ]
)
