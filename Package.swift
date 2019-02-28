// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LGNKit-Swift",
    products: [
        .library(name: "LGNCore", targets: ["LGNCore"]),
        .library(name: "LGNP", targets: ["LGNP"]),
        .library(name: "LGNPContenter", targets: ["LGNPContenter"]),
        .library(name: "LGNS", targets: ["LGNS"]),
        .library(name: "LGNC", targets: ["LGNC"]),
        .library(name: "Entita", targets: ["Entita"]),
        .library(name: "Entita2", targets: ["Entita2"]),
        .library(name: "Entita2FDB", targets: ["Entita2FDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "1.8.0")),

        // used by LGNPContenter
        .package(url: "https://github.com/kirilltitov/MessagePack.git", .branch("master")),

        // used by Entita2
        .package(url: "https://github.com/kirilltitov/SwiftMsgPack.git", .branch("master")),

        // used by Entita2FDB
        .package(url: "https://github.com/kirilltitov/FDBSwift.git", .branch("master")),

        // used by LGNP
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMajor(from: "0.9.0")),
        .package(url: "https://github.com/1024jp/GzipSwift.git", .upToNextMajor(from: "4.0.0")),
    ],
    targets: [
        .target(
            name: "LGNCore",
            dependencies: ["NIO"]
        ),
        .target(
            name: "LGNP",
            dependencies: ["LGNCore", "Gzip", "CryptoSwift"]
        ),
        .target(
            name: "LGNPContenter",
            dependencies: ["LGNCore", "LGNP", "SwiftMsgPack"]
        ),
        .target(
            name: "LGNS",
            dependencies: ["LGNCore", "LGNP", "NIO"]
        ),
        .target(
            name: "LGNC",
            dependencies: ["LGNCore", "Entita", "LGNS", "LGNP", "LGNPContenter", "NIO", "NIOHTTP1"]
        ),
        .target(
            name: "Entita",
            dependencies: ["LGNCore", "NIO"]
        ),
        .target(
            name: "Entita2",
            dependencies: ["LGNCore", "MessagePack", "NIO"]
        ),
        .target(
            name: "Entita2FDB",
            dependencies: ["LGNCore", "Entita2", "FDB", "NIO"]
        ),
        .testTarget(
            name: "LGNKitTests",
            dependencies: [
                "LGNCore",
                "LGNP",
                "LGNPContenter",
                "LGNS",
                "LGNC",
                "Entita",
                "Entita2",
                "Entita2FDB",
            ]
        ),
    ]
)
