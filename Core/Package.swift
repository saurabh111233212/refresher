// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RefresherCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "RefresherCore", targets: ["RefresherCore"])],
    targets: [
        .target(name: "RefresherCore"),
        .testTarget(name: "RefresherCoreTests", dependencies: ["RefresherCore"]),
    ]
)
