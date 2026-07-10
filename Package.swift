// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scoot",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ScootCore",
            path: "Sources/ScootCore"
        ),
        .executableTarget(
            name: "Scoot",
            dependencies: ["ScootCore"],
            path: "Sources/Scoot"
        ),
        .testTarget(
            name: "ScootTests",
            dependencies: ["ScootCore"],
            path: "Tests/ScootTests"
        )
    ]
)
