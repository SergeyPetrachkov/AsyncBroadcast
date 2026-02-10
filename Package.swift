// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AsyncBroadcast",
    platforms: [
        .macOS(.v13), .iOS(.v16)
    ],
    products: [
        .library(
            name: "AsyncBroadcast",
            targets: ["AsyncBroadcast"]
        ),
    ],
    targets: [
        .target(
            name: "AsyncBroadcast"
        ),
        .testTarget(
            name: "AsyncBroadcastTests",
            dependencies: ["AsyncBroadcast"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
