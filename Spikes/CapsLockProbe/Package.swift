// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CapsLockProbe",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CapsLockProbeCore", targets: ["CapsLockProbeCore"]),
        .executable(name: "caps-lock-probe", targets: ["CapsLockProbe"])
    ],
    targets: [
        .target(name: "CapsLockProbeCore"),
        .executableTarget(name: "CapsLockProbe", dependencies: ["CapsLockProbeCore"]),
        .testTarget(name: "CapsLockProbeCoreTests", dependencies: ["CapsLockProbeCore"])
    ]
)
