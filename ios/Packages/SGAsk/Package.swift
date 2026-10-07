// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGAsk",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SGAsk", targets: ["SGAsk"])],
    dependencies: [.package(path: "../SGModels")],
    targets: [
        .target(
            name: "SGAsk",
            dependencies: ["SGModels"],
            resources: [.process("Resources/Localization"), .process("Resources/ask_keywords.json")]
        ),
        .testTarget(name: "SGAskTests", dependencies: ["SGAsk", "SGModels"])
    ],
    swiftLanguageVersions: [.v5]
)
