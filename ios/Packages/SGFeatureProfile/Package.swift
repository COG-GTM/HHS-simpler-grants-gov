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
        .package(path: "../SGCore"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.17.6")
    ],
    targets: [
        .target(
            name: "SGFeatureProfile",
            dependencies: ["SGModels", "SGDesign", "SGCore"],
            resources: [
                .process("Resources/Localization"),
                .process("Resources/Roadmap")
            ]
        ),
        .testTarget(
            name: "SGFeatureProfileTests",
            dependencies: [
                "SGFeatureProfile",
                "SGModels",
                "SGCore",
                "SGDesign",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
