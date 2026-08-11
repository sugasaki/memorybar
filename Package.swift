// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "truemem",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "truemem", targets: ["TrueMem"])
    ],
    targets: [
        .target(
            name: "CMachSupport",
            path: "Sources/CMachSupport",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "TrueMem",
            dependencies: ["CMachSupport"],
            path: "Sources/TrueMem"
        ),
        .testTarget(
            name: "TrueMemTests",
            dependencies: ["TrueMem"],
            path: "Tests/TrueMemTests"
        ),
    ]
)
