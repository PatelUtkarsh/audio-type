// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioType",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AudioType", targets: ["AudioType"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AudioType",
            dependencies: [],
            path: "AudioType",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
