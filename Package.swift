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
            dependencies: ["WhisperKit"],
            path: "AudioType",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-import-objc-header", "Bridging/AudioType-Bridging-Header.h"])
            ],
            linkerSettings: [
                .linkedLibrary("whisper", .when(platforms: [.macOS])),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ApplicationServices"),
                .unsafeFlags(["-L../whisper.cpp/build/src", "-L../whisper.cpp/build"])
            ]
        ),
        .target(
            name: "WhisperKit",
            dependencies: [],
            path: "WhisperKit",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../whisper.cpp/include"),
                .headerSearchPath("../whisper.cpp/ggml/include")
            ],
            linkerSettings: [
                .linkedLibrary("whisper"),
                .linkedLibrary("ggml"),
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .unsafeFlags(["-L../whisper.cpp/build/src", "-L../whisper.cpp/build/ggml/src"])
            ]
        )
    ]
)
