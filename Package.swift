// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pesty",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pesty", targets: ["Pesty"])
    ],
    dependencies: [
        .package(path: "Shared")
    ],
    targets: [
        .executableTarget(
            name: "Pesty",
            dependencies: [
                .product(name: "PestyShared", package: "Shared")
            ],
            path: "Sources/Pesty",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "PestyTests",
            dependencies: ["Pesty"]
        )
    ],
    swiftLanguageModes: [.v5]
)
