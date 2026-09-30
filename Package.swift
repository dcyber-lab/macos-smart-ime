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
            name: "RimeBridge",
            targets: ["RimeBridge"]
        ),
        .library(
            name: "IMEHostCore",
            targets: ["IMEHostCore"]
        ),
        .library(
            name: "EnglishEngine",
            targets: ["EnglishEngine"]
        ),
        .library(
            name: "UserData",
            targets: ["UserData"]
        ),
    ],
    targets: [
        .systemLibrary(
            name: "CLibrime",
            path: "packages/rime-bridge/Sources/CLibrime",
            pkgConfig: "rime",
            providers: [
                .brew(["librime"]),
            ]
        ),
        .target(
            name: "SharedModels",
            path: "packages/shared-models/Sources/SharedModels"
        ),
        .target(
            name: "RimeBridge",
            dependencies: [
                "CLibrime",
                "SharedModels",
            ],
            path: "packages/rime-bridge/Sources/RimeBridge"
        ),
        .testTarget(
            name: "RimeBridgeTests",
            dependencies: [
                "RimeBridge",
                "SharedModels",
            ],
            path: "packages/rime-bridge/Tests/RimeBridgeTests"
        ),
        .target(
            name: "UserData",
            path: "packages/user-data/Sources/UserData"
        ),
        .testTarget(
            name: "UserDataTests",
            dependencies: [
                "UserData",
            ],
            path: "packages/user-data/Tests/UserDataTests"
        ),
        .target(
            name: "EnglishEngine",
            dependencies: [
                "SharedModels",
                "UserData",
            ],
            path: "packages/english-engine/Sources/EnglishEngine",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "EnglishEngineTests",
            dependencies: [
                "EnglishEngine",
                "SharedModels",
            ],
            path: "packages/english-engine/Tests/EnglishEngineTests"
        ),
        .target(
            name: "IMEHostCore",
            dependencies: [
                "SharedModels",
                "RimeBridge",
                "EnglishEngine",
                "UserData",
            ],
            path: "apps/ime/Sources/IMEHostCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("InputMethodKit"),
            ]
        ),
        .testTarget(
            name: "IMEHostCoreTests",
            dependencies: [
                "IMEHostCore",
                "SharedModels",
            ],
            path: "apps/ime/Tests/IMEHostCoreTests"
        ),
    ]
)
