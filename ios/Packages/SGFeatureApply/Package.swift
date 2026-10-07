// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGFeatureApply",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SGFeatureApply", targets: ["SGFeatureApply"])],
    dependencies: [
        .package(path: "../SGModels"),
        .package(path: "../SGDesign"),
        .package(path: "../SGCore"),
        .package(path: "../SGForms")
    ],
    targets: [
        .target(
            name: "SGFeatureApply",
            dependencies: ["SGModels", "SGDesign", "SGCore", "SGForms"],
            resources: [.process("Resources/Localization")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
