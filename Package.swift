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
            dependencies: ["WhisperWrapper"],
            path: "AudioType",
            exclude: ["Bridging"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .target(
            name: "WhisperWrapper",
            dependencies: [],
            path: "WhisperWrapper"
        )
    ]
)
