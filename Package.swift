// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AVT_helper",
    defaultLocalization: "ru",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AVT_helper", targets: ["AVT_helper"])
    ],
    targets: [
        .executableTarget(
            name: "AVT_helper",
            resources: [.process("Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "AVT_helperTests", dependencies: ["AVT_helper"]),
    ]
)
