// Local mirror of SGDesign Theme.swift tokens, which are internal to SGDesign. Delete this file once SGDesign exposes SG publicly.
import SwiftUI

enum SG {
    private static func color(hex: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    enum C {
        static let ink = SG.color(hex: 0x14171F)
        static let body = SG.color(hex: 0x2A2E38)
        static let muted = SG.color(hex: 0x5A6070)
        static let subtle = SG.color(hex: 0x8A8F99)
        static let canvas = SG.color(hex: 0xF6F6F3)
        static let surface = Color.white
        static let field = SG.color(hex: 0xEAEAE5)
        static let line = SG.color(hex: 0xE4E4DF)
        static let control = SG.color(hex: 0xD5D5D0)
        static let navy = SG.color(hex: 0x1F3D6E)
        static let navyTint = SG.color(hex: 0xE8EDF5)
        static let disabled = SG.color(hex: 0xA9B3C4)
    }

    enum F {
        static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
            .custom(
                weight == .regular ? "SourceSerif4-Regular" : "SourceSerif4-SemiBold",
                size: size,
                relativeTo: .title
            )
        }

        static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            let name: String
            switch weight {
            case .medium: name = "PublicSans-Medium"
            case .semibold: name = "PublicSans-SemiBold"
            case .bold: name = "PublicSans-Bold"
            default: name = "PublicSans-Regular"
            }
            return .custom(name, size: size, relativeTo: .body)
        }

        static let largeTitle = serif(34)
        static let cardTitle = serif(18)
        static let answer = serif(17, .regular)
        static let section = sans(20, .semibold)
    }
}
