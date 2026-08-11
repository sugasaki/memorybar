// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "memory-info-menubar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "memory-info-menubar", targets: ["MemoryInfoMenubar"])
    ],
    targets: [
        .executableTarget(
            name: "MemoryInfoMenubar",
            path: "Sources/MemoryInfoMenubar"
        ),
        .testTarget(
            name: "MemoryInfoMenubarTests",
            dependencies: ["MemoryInfoMenubar"],
            path: "Tests/MemoryInfoMenubarTests"
        ),
    ]
)
