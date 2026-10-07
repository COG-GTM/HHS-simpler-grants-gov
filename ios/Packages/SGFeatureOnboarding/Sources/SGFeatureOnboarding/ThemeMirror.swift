import SwiftUI

// SGDesign's Theme.swift tokens (SG, PrimaryButton) are internal to SGDesign, so this module keeps
// a value-for-value mirror. Delete this file once SGDesign makes them public; module-local types
// shadow imported ones, so call sites will not change.
enum SG {
    enum C {
        static let ink = Color(sgHex: 0x14171F)
        static let muted = Color(sgHex: 0x5A6070)
        static let subtle = Color(sgHex: 0x8A8F99)
        static let canvas = Color(sgHex: 0xF6F6F3)
        static let surface = Color.white
        static let control = Color(sgHex: 0xD5D5D0)
        static let navy = Color(sgHex: 0x1F3D6E)
        static let navyPress = Color(sgHex: 0x16305A)
        static let navyTint = Color(sgHex: 0xE8EDF5)
        static let disabled = Color(sgHex: 0xA9B3C4)
    }

    enum F {
        static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
            .custom(weight == .regular ? "SourceSerif4-Regular" : "SourceSerif4-SemiBold", size: size, relativeTo: .title)
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
        static let title = serif(28)
        static let bodyText = sans(16)
        static let button = sans(17, .semibold)
        static let caption = sans(13)
        static let overline = sans(12, .semibold)
    }

    enum R { static let button: CGFloat = 16 }
    enum S { static let margin: CGFloat = 20, xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 28 }
}

struct PrimaryButton: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SG.F.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                enabled ? (configuration.isPressed ? SG.C.navyPress : SG.C.navy) : SG.C.disabled,
                in: RoundedRectangle(cornerRadius: SG.R.button, style: .continuous)
            )
    }
}

private extension Color {
    init(sgHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
