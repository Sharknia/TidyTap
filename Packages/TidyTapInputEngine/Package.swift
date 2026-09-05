// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TidyTapInputEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TidyTapInputEngine", targets: ["TidyTapInputEngine"])
    ],
    targets: [
        .target(name: "TidyTapInputEngine"),
        .testTarget(
            name: "TidyTapInputEngineTests",
            dependencies: ["TidyTapInputEngine"]
        )
    ]
)
