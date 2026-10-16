// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SlopometerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SlopometerCore", targets: ["SlopometerCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(
            name: "SlopometerCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "SlopometerCoreTests", dependencies: ["SlopometerCore"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
