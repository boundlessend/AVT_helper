// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AVT_helper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AVT_helper", targets: ["AVT_helper"])
    ],
    targets: [
        .executableTarget(name: "AVT_helper")
    ]
)
