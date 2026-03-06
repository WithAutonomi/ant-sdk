// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AntFfi",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "AntFfi", targets: ["AntFfi"]),
    ],
    targets: [
        .target(
            name: "AntFfi",
            path: "AntFfi/Generated"
        ),
    ]
)
