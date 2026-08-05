// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scoot",
    platforms: [.macOS(.v13)],
    dependencies: [
        // v2.x ships #Preview macros that require Xcode's PreviewsMacros plugin (CLT-only builds fail).
        // Pin to the last CLT-compatible release (1.15.0).
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.15.0"),
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.0.0"),
        // Pure Swift, no macros — builds fine under Command Line Tools.
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ScootCore",
            path: "Sources/ScootCore"
        ),
        .executableTarget(
            name: "Scoot",
            dependencies: [
                "ScootCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
            ],
            path: "Sources/Scoot"
        ),
        .executableTarget(
            name: "ScootCLI",
            dependencies: [
                "ScootCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ScootCLI"
        ),
        .testTarget(
            name: "ScootTests",
            dependencies: ["ScootCore", "ScootCLI"],
            path: "Tests/ScootTests"
        )
    ]
)
