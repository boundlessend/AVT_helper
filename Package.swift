// swift-tools-version: 6.0

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
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "AVT_helperTests", dependencies: ["AVT_helper"]),
    ]
)
