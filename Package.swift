// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Flint",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Flint", targets: ["Flint"])
    ],
    targets: [
        .executableTarget(
            name: "Flint",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "FlintTests",
            dependencies: ["Flint"]
        )
    ]
)
