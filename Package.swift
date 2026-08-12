// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "memorybar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "memorybar", targets: ["MemoryBar"])
    ],
    targets: [
        .target(
            name: "CMachSupport",
            path: "Sources/CMachSupport",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MemoryBar",
            dependencies: ["CMachSupport"],
            path: "Sources/MemoryBar"
        ),
        .testTarget(
            name: "MemoryBarTests",
            dependencies: ["MemoryBar"],
            path: "Tests/MemoryBarTests"
        ),
    ]
)
