// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "imekeeper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "imekeeper", targets: ["imekeeper"]),
        .library(name: "IMEKeeperCore", targets: ["IMEKeeperCore"])
    ],
    targets: [
        .target(
            name: "IMEKeeperCore",
            dependencies: [],
            path: "Sources/IMEKeeperCore"
        ),
        .executableTarget(
            name: "imekeeper",
            dependencies: ["IMEKeeperCore"],
            path: "Sources/imekeeper"
        ),
        .testTarget(
            name: "IMEKeeperTests",
            dependencies: ["IMEKeeperCore"],
            path: "Tests/IMEKeeperTests"
        ),
    ]
)
