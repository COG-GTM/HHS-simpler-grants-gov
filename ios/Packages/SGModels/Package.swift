// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGModels",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SGModels", targets: ["SGModels"])],
    targets: [
        .target(name: "SGModels"),
        .testTarget(
            name: "SGModelsTests",
            dependencies: ["SGModels"],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
