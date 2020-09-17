// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "IntegrationTests",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "0.2.0")),
        .package(name: "LGNKit", path: "../")
    ],
    targets: [
        .target(
            name: "IntegrationTests",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "LGNC", package: "LGNKit"),
            ]
        ),
        .testTarget(name: "IntegrationTestsTests", dependencies: ["IntegrationTests"]),
    ]
)
