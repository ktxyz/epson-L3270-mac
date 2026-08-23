// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "L3270",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "L3270Core",
            path: "Sources/L3270Core"
        ),
        .executableTarget(
            name: "l3270",
            dependencies: [
                "L3270Core",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/l3270"
        ),
        .executableTarget(
            name: "L3270App",
            dependencies: ["L3270Core"],
            path: "Sources/L3270App"
        ),
        .executableTarget(
            name: "debugtool",
            dependencies: ["L3270Core"],
            path: "Sources/debugtool"
        ),
        .testTarget(
            name: "L3270Tests",
            dependencies: ["L3270Core"],
            path: "Tests/L3270Tests",
            resources: [.process("Fixtures")]
        ),
    ]
)
