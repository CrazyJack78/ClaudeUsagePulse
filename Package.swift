// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsagePulse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeUsagePulse",
            path: "Sources/ClaudeUsagePulse",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"]
        )
    ]
)
