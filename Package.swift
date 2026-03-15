// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "macos-smart-ime",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "SharedModels",
            targets: ["SharedModels"]
        ),
        .library(
            name: "IMEHostCore",
            targets: ["IMEHostCore"]
        ),
    ],
    targets: [
        .target(
            name: "SharedModels",
            path: "packages/shared-models/Sources/SharedModels"
        ),
        .target(
            name: "IMEHostCore",
            dependencies: [
                "SharedModels",
            ],
            path: "apps/ime/Sources/IMEHostCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("InputMethodKit"),
            ]
        ),
    ]
)
