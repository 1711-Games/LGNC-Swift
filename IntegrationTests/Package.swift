// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "IntegrationTests",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(name: "LGNKit", url: "git@github.com:1711-games/LGNKit-Swift.git", .branch("master")),
    ],
    targets: [
        .target(
            name: "IntegrationTests",
            dependencies: [
            .product(name: "LGNC", package: "LGNKit"),
            ]
        ),
        .testTarget(name: "IntegrationTestsTests", dependencies: ["IntegrationTests"]),
    ]
)
