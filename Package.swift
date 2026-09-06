// swift-tools-version: 6.0

import PackageDescription

/// `EchnoCore` is the Swift port of the `@tornotron/echno-core` TypeScript package:
/// domain models, API services and observable stores, shared by every Echno client.
///
/// Modules are ported one at a time from echno-core via the `echno-apple` skill.
/// See `local-docs/echno-ios-port-log.md` for what has been ported and from which
/// echno-core commit.
let package = Package(
    name: "EchnoCore",
    platforms: [
        .iOS(.v18),
        // The package is Foundation-only, so it also builds for macOS. That is
        // what lets `swift build` / `swift test` run the logic tests in CI in
        // seconds without booting a simulator. The app itself is iOS-only.
        .macOS(.v14)
    ],
    products: [
        .library(name: "EchnoCore", targets: ["EchnoCore", "EchnoAPI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0")
    ],
    targets: [
        // Generated from the backend's OpenAPI document. Never hand-edited —
        // run `Scripts/sync-openapi.sh` and rebuild instead.
        .target(
            name: "EchnoAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            exclude: ["openapi.source"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                // The generator emits `public import Foundation` in files that
                // do not need it, which is a warning under Swift 6. They are
                // not ours to fix and there are hundreds; left on, they bury
                // the warnings that are ours.
                .unsafeFlags(["-suppress-warnings"])
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "EchnoCore",
            dependencies: [
                "EchnoAPI",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "EchnoCoreTests",
            dependencies: ["EchnoCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
