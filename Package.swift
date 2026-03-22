// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "EcowittLocal",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "EcowittLocal",
            targets: ["EcowittLocal"]
        ),
    ],
    targets: [
        .target(
            name: "EcowittLocal"
        ),
    ]
)
