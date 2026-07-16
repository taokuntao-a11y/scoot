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
        .testTarget(
            name: "ScootTests",
            dependencies: ["ScootCore"],
            path: "Tests/ScootTests"
        )
    ]
)
