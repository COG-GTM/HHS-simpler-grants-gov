// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SGCore", targets: ["SGCore"])],
    dependencies: [
        .package(path: "../SGModels"),
        .package(path: "../SGAsk")
    ],
    targets: [
        .target(name: "SGCore", dependencies: ["SGModels", "SGAsk"])
    ],
    swiftLanguageVersions: [.v5]
)
