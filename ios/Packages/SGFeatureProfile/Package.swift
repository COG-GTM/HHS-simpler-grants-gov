// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGFeatureProfile",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SGFeatureProfile", targets: ["SGFeatureProfile"])],
    dependencies: [
        .package(path: "../SGModels"),
        .package(path: "../SGDesign"),
        .package(path: "../SGCore")
    ],
    targets: [
        .target(
            name: "SGFeatureProfile",
            dependencies: ["SGModels", "SGDesign", "SGCore"],
            resources: [.process("Resources/Localization")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
