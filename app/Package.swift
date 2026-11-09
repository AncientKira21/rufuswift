// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rufus",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/moreSwift/swift-cross-ui.git", exact: "0.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Rufus",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui")
            ],
            path: "desktop",
            exclude: ["build"]
        )
    ],
    swiftLanguageModes: [.v5]
)
