// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MusicPlayer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MusicPlayer",
            targets: ["MusicPlayer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MusicPlayer"
        )
    ]
)
