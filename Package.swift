// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyboardSound",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeyboardSound",
            path: "Sources/KeyboardSound"
        ),
        .testTarget(
            name: "KeyboardSoundTests",
            dependencies: ["KeyboardSound"],
            path: "Tests/KeyboardSoundTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
