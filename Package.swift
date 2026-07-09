// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Flint",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Flint", targets: ["Flint"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Flint",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Security"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "FlintTests",
            dependencies: ["Flint"]
        )
    ]
)
