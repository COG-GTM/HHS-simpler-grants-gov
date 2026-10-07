// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGFeatureSearch",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SGFeatureSearch", targets: ["SGFeatureSearch"])],
    dependencies: [
        .package(path: "../SGModels"),
        .package(path: "../SGDesign"),
        .package(path: "../SGCore")
    ],
    targets: [
        .target(
            name: "SGFeatureSearch",
            dependencies: ["SGModels", "SGDesign", "SGCore"],
            resources: [.process("Resources/Localization")]
        ),
        .testTarget(
            name: "SGFeatureSearchTests",
            dependencies: ["SGFeatureSearch", "SGModels"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
