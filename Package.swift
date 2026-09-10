// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WindowPin",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WindowPin",
            path: "Sources/WindowPin"
        )
    ]
)
