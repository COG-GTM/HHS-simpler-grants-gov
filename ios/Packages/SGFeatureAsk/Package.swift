// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGFeatureAsk",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SGFeatureAsk", targets: ["SGFeatureAsk"])],
    dependencies: [
        .package(path: "../SGModels"),
        .package(path: "../SGDesign"),
        .package(path: "../SGCore"),
        .package(path: "../SGAsk")
    ],
    targets: [
        .target(
            name: "SGFeatureAsk",
            dependencies: ["SGModels", "SGDesign", "SGCore", "SGAsk"],
            resources: [.process("Resources/Localization")]
        ),
        .testTarget(
            name: "SGFeatureAskTests",
            dependencies: ["SGFeatureAsk", "SGAsk", "SGModels"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
