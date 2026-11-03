// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LocalSTT",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        // Logic only — no AppKit, audio or TCC dependencies — keeping it unit-testable.
        .target(
            name: "LocalSTTCore",
            path: "Sources/LocalSTTCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "LocalSTT",
            dependencies: ["LocalSTTCore"],
            path: "Sources/LocalSTT",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "LocalSTTCoreTests",
            dependencies: ["LocalSTTCore"],
            path: "Tests/LocalSTTCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
