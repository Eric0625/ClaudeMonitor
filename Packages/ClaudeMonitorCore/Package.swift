// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeMonitorCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeMonitorCore", targets: ["ClaudeMonitorCore"]),
    ],
    targets: [
        .target(name: "ClaudeMonitorCore"),
        .testTarget(
            name: "ClaudeMonitorCoreTests",
            dependencies: ["ClaudeMonitorCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
