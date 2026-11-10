// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacCleanerBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MacCleanerBar", path: "Sources/MacCleanerBar")
    ]
)
