import SwiftUI

/// SGDesign's `SG` token namespace is `internal` to SGDesign, so it can't be
/// referenced from this package. These mirror the values in
/// `SGDesign/Theme.swift` one-for-one; switch to `SG.C/F/R/S` once SGDesign
/// makes them public.
enum FormTheme {
    enum C {
        static let ink = Color(formHex: 0x14171F)
        static let muted = Color(formHex: 0x5A6070)
        static let subtle = Color(formHex: 0x8A8F99)
        static let canvas = Color(formHex: 0xF6F6F3)
        static let surface = Color.white
        static let line = Color(formHex: 0xE4E4DF)
        static let control = Color(formHex: 0xD5D5D0)
        static let navy = Color(formHex: 0x1F3D6E)
        static let navyTint = Color(formHex: 0xE8EDF5)
        static let green = Color(formHex: 0x1E7A4C)
        static let red = Color(formHex: 0xB42318)
        static let openBg = Color(formHex: 0xE7F3EC)
        static let openFg = Color(formHex: 0x14583A)
    }

    enum F {
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

        static func serif(_ size: CGFloat) -> Font {
            .custom("SourceSerif4-SemiBold", size: size, relativeTo: .title)
        }

        static let bodyText = sans(16)
        static let label = sans(14, .semibold)
        static let caption = sans(13)
        static let section = sans(18, .semibold)
        static let mono = Font.system(.body, design: .monospaced)
    }

    enum R {
        static let input: CGFloat = 12
        static let card: CGFloat = 18
        static let row: CGFloat = 14
    }

    enum S {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    static let controlHeight: CGFloat = 48
}

extension Color {
    init(formHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
