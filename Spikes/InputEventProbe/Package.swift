// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "InputEventProbe",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "InputEventProbe", targets: ["InputEventProbe"]),
        .library(name: "InputEventProbeCore", targets: ["InputEventProbeCore"])
    ],
    targets: [
        .target(name: "InputEventProbeCore"),
        .executableTarget(
            name: "InputEventProbe",
            dependencies: ["InputEventProbeCore"]
        ),
        .testTarget(
            name: "InputEventProbeCoreTests",
            dependencies: ["InputEventProbeCore"]
        )
    ]
)
