// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SGDesign",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SGDesign", targets: ["SGDesign"])
    ],
    targets: [
        .target(
            name: "SGDesign",
            resources: [
                .copy("Resources/Fonts"),
                .process("Resources/Localization")
            ]
        )
    ]
)
