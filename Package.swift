// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "LGNC-Swift",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "LGNCore", targets: ["LGNCore"]),
        .library(name: "LGNP", targets: ["LGNP"]),
        .library(name: "LGNPContenter", targets: ["LGNPContenter"]),
        .library(name: "LGNS", targets: ["LGNS"]),
        .library(name: "LGNC", targets: ["LGNC"]),
        .library(name: "Entita", targets: ["Entita"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.33.0"),

        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.2.1"),

        // used by LGNPContenter
        .package(url: "https://github.com/kirilltitov/SwiftMsgPack.git", from: "2.0.1"),

        // used by LGNP
        .package(url: "https://github.com/apple/swift-crypto.git", from: "1.0.0"),
        .package(name: "Gzip", url: "https://github.com/1024jp/GzipSwift.git", from: "5.1.1"),

        // used by LGNCore
        .package(url: "https://github.com/1711-games/lgn-config", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "LGNCore",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "LGNConfig", package: "lgn-config"),
            ],
            exclude: ["README.md"]
        ),
        .target(
            name: "LGNP",
            dependencies: [
                "LGNCore",
                "Gzip",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            exclude: ["README.md", "logo.png"]
        ),
        .target(
            name: "LGNPContenter",
            dependencies: [
                "LGNCore",
                "LGNP",
                .product(name: "SwiftMsgPack", package: "SwiftMsgPack"),
            ],
            exclude: ["README.md"]
        ),
        .target(
            name: "LGNS",
            dependencies: [
                "LGNCore",
                "LGNP",
                .product(name: "NIO", package: "swift-nio"),
            ],
            exclude: ["README.md", "logo.png"]
        ),
        .target(
            name: "LGNC",
            dependencies: [
                "LGNCore",
                "Entita",
                "LGNS",
                "LGNP",
                "LGNPContenter",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ],
            exclude: ["README.md"]
        ),
        .target(name: "Entita", dependencies: [], exclude: ["README.md"]),
        .testTarget(
            name: "LGNCSwiftTests",
            dependencies: [
                "LGNCore",
                "LGNP",
                "LGNPContenter",
                "LGNS",
                "LGNC",
                "Entita",
            ],
            exclude: ["Schema"]
        ),
    ]
)
