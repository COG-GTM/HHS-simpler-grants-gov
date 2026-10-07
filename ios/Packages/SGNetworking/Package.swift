// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGNetworking",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SGNetworking", targets: ["SGNetworking"])],
    dependencies: [
        .package(path: "../SGModels"),
        .package(path: "../SGCore")
    ],
    targets: [
        .target(name: "SGNetworking", dependencies: ["SGModels", "SGCore"])
    ],
    swiftLanguageVersions: [.v5]
)
