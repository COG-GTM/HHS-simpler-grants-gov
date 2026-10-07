// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGForms",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SGForms", targets: ["SGForms"])],
    dependencies: [
        .package(path: "../SGModels"),
        .package(path: "../SGDesign")
    ],
    targets: [
        .target(
            name: "SGForms",
            dependencies: ["SGModels", "SGDesign"],
            resources: [.process("Resources/Localization"), .copy("Resources/Samples")]
        ),
        .testTarget(
            name: "SGFormsTests",
            dependencies: ["SGForms", "SGModels"],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
