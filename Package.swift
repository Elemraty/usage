// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UsageOverlay",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "UsageOverlay",
            path: "Sources/UsageOverlay"
        )
    ]
)
