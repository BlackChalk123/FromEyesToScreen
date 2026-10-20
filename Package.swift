// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EyesToScreen",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EyesToScreen", targets: ["EyesToScreen"]),
               .executable(name: "Suishi", targets: ["Suishi"])],
    targets: [
        .target(name: "MotionCore"),
        .target(name: "MediaCore"),
        .target(name: "RotationCore"),
        .executableTarget(name: "Suishi", dependencies: ["RotationCore", "MediaCore"]),
        .executableTarget(name: "EyesToScreen", dependencies: ["MotionCore", "MediaCore"])
    ]
)
