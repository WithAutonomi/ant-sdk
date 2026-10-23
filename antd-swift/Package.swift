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
        // SwiftNIO security floors. grpc-swift-nio-transport would accept older
        // releases, and a Swift 6.0 toolchain resolves to them, because these
        // fixes need swift-tools-version 6.1:
        //   swift-nio 2.100.0       GHSA-cq87-8r7h-962v, GHSA-r3rc-9hpw-54v9, GHSA-rj37-6j9x-74q6
        //   swift-nio-http2 1.44.0  GHSA-4px2-pw77-vc85
        //   swift-nio-extras 1.34.1 GHSA-6ph5-fww6-vfwv
        // So antd-swift now needs Swift 6.1 or newer. The products below are the
        // ones GRPCNIOTransportHTTP2 already links; naming them on AntdSdk is what
        // makes these floors apply to apps that depend on antd-swift (SwiftPM drops
        // a dependency's packages that none of its targets use).
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.100.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.44.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.34.1"),
    ],
    targets: [
        .target(
            name: "AntdSdk",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
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
        .testTarget(
            name: "AntdExamplesTests",
            dependencies: ["AntdExamples", "AntdSdk"]
        ),
    ]
)
