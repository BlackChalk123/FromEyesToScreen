// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EyesToScreen",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EyesToScreen", targets: ["EyesToScreen"])],
    targets: [
        .target(name: "MotionCore"),
        .target(name: "MediaCore"),
        .executableTarget(name: "EyesToScreen", dependencies: ["MotionCore", "MediaCore"])
    ]
)
