// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGSampleData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SGSampleData", targets: ["SGSampleData"])],
    dependencies: [.package(path: "../SGModels")],
    targets: [
        .target(name: "SGSampleData", dependencies: ["SGModels"])
    ],
    swiftLanguageVersions: [.v5]
)
