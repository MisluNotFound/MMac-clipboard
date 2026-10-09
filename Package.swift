// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "MMacClipboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MMacClipboard",
            path: "Sources/MMacClipboard"
        )
    ],
    swiftLanguageModes: [.v5]
)
