// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LookSize",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LookSizeCore", targets: ["LookSizeCore"]),
        .executable(name: "LookSize", targets: ["LookSizeApp"]),
        .executable(name: "looksize-inspect", targets: ["LookSizeInspect"])
    ],
    targets: [
        .target(
            name: "LookSizeCore",
            path: "Sources/LookSizeCore"
        ),
        .executableTarget(
            name: "LookSizeApp",
            dependencies: ["LookSizeCore"],
            path: "Sources/LookSizeApp"
        ),
        .executableTarget(
            name: "LookSizeInspect",
            dependencies: ["LookSizeCore"],
            path: "Sources/LookSizeInspect"
        ),
        .testTarget(
            name: "LookSizeCoreTests",
            dependencies: ["LookSizeCore"],
            path: "Tests/LookSizeCoreTests"
        )
    ]
)
