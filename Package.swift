// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EnergyShape",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EnergyShape",
            targets: ["EnergyShape"]
        ),
    ],
    dependencies: [
        // No external dependencies
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "EnergyShape",
            dependencies: [],
            path: "Sources/EnergyShape",
            exclude: [],
            sources: nil,
            resources: [
                // 包含 Metal shader 源文件，运行时编译
                .process("Shaders.metal")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "EnergyShapeTests",
            dependencies: ["EnergyShape"],
            path: "Tests/EnergyShapeTests"
        ),
    ]
)
