// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsagePulse",
    platforms: [.macOS(.v14)],
    targets: [
        // Reine Logik ohne AppKit: Cookie-Auswertung und Auswertung der API-Antwort.
        // Als eigenes Target, damit es testbar ist — ein executableTarget ist es nicht.
        .target(
            name: "ClaudeUsageCore",
            path: "Sources/ClaudeUsageCore"
        ),
        .executableTarget(
            name: "ClaudeUsagePulse",
            dependencies: ["ClaudeUsageCore"],
            path: "Sources/ClaudeUsagePulse",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"],
            path: "Tests/ClaudeUsageCoreTests"
        )
    ]
)
