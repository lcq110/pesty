// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PestyShared",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PestyShared", targets: ["PestyShared"]),
    ],
    targets: [
        .target(name: "PestyShared"),
        .testTarget(
            name: "PestySharedTests",
            dependencies: ["PestyShared"]
        ),
    ]
)
