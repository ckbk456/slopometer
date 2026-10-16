// swift-tools-version: 6.1
import PackageDescription

// Pins the formatter so local and CI lint agree regardless of the selected Xcode.
let package = Package(
    name: "SlopometerTools",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-format.git", exact: "601.0.0")
    ],
    targets: []
)
