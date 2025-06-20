// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AudioHelper",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AudioHelper", targets: ["AudioHelper"])],
    targets: [
        .executableTarget(
            name: "AudioHelper",
            exclude: ["Info.plist"]      // ← suppress “unhandled file” warning
        )
    ]
)
