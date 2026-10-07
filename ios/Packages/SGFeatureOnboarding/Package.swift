// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGFeatureOnboarding",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SGFeatureOnboarding", targets: ["SGFeatureOnboarding"])],
    dependencies: [
        .package(path: "../SGModels"),
        .package(path: "../SGDesign"),
        .package(path: "../SGCore")
    ],
    targets: [
        .target(
            name: "SGFeatureOnboarding",
            dependencies: ["SGModels", "SGDesign", "SGCore"],
            resources: [.process("Resources/Localization")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
