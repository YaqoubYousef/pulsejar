// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PulseJarCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PulseJarCore", targets: ["PulseJarCore"]),
    ],
    targets: [
        .target(name: "PulseJarCore"),
        .testTarget(name: "PulseJarCoreTests", dependencies: ["PulseJarCore"]),
    ]
)
