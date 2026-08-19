// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReelForge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ReelForgeCore", targets: ["ReelForgeCore"])
    ],
    targets: [
        .target(
            name: "ReelForgeCore",
            path: "Sources/ReelForgeCore",
            resources: [
                .copy("Resources/presets"),
                .copy("Resources/caption-styles"),
                .copy("Resources/fonts"),
                .copy("Resources/workflows"),
                .copy("Resources/models")
            ]
        ),
        .testTarget(
            name: "ReelForgeTests",
            dependencies: ["ReelForgeCore"],
            path: "Tests/ReelForgeTests"
        )
    ]
)
