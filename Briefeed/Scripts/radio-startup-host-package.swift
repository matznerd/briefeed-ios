// swift-tools-version: 6.0
import PackageDescription

// This dependency-free package is copied to a disposable directory by the runner.
let package = Package(
    name: "RadioStartupHostTests",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "Briefeed", path: "Sources"),
        .testTarget(name: "BriefeedTests", dependencies: ["Briefeed"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
