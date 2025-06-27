// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mcpx",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "mcpx",
            targets: ["mcpx"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "mcpx",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources"
        )
    ]
)
