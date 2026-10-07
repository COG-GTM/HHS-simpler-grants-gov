import SwiftUI

// Mirrors SGDesign Theme tokens until SGDesign exposes them publicly.
enum ApplyTheme {
    enum C {
        static let ink = applyColor(hex: 0x14171F)
        static let body = applyColor(hex: 0x2A2E38)
        static let muted = applyColor(hex: 0x5A6070)
        static let subtle = applyColor(hex: 0x8A8F99)
        static let canvas = applyColor(hex: 0xF6F6F3)
        static let surface = Color.white
        static let field = applyColor(hex: 0xEAEAE5)
        static let line = applyColor(hex: 0xE4E4DF)
        static let lineSoft = applyColor(hex: 0xEFEFEA)
        static let control = applyColor(hex: 0xD5D5D0)
        static let navy = applyColor(hex: 0x1F3D6E)
        static let navyPress = applyColor(hex: 0x16305A)
        static let navyTint = applyColor(hex: 0xE8EDF5)
        static let disabled = applyColor(hex: 0xA9B3C4)
        static let green = applyColor(hex: 0x1E7A4C)
        static let red = applyColor(hex: 0xB42318)
        static let openBg = applyColor(hex: 0xE7F3EC)
        static let openFg = applyColor(hex: 0x14583A)
        static let soonBg = applyColor(hex: 0xFBEDEB)
        static let soonFg = applyColor(hex: 0x8A1C13)
        static let foreBg = applyColor(hex: 0xFFF3DD)
        static let foreFg = applyColor(hex: 0x7A4A00)
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

        static let mono = Font.system(size: 13, weight: .medium, design: .monospaced)
    }

    enum R {
        static let card: CGFloat = 18
        static let button: CGFloat = 16
        static let row: CGFloat = 14
        static let input: CGFloat = 12
    }

    enum S {
        static let margin: CGFloat = 20
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 28
    }
}

private func applyColor(hex: UInt32) -> Color {
    Color(
        .sRGB,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        opacity: 1
    )
}

struct ApplyPrimaryButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ApplyTheme.F.sans(17, .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                isEnabled
                    ? (configuration.isPressed ? ApplyTheme.C.navyPress : ApplyTheme.C.navy)
                    : ApplyTheme.C.disabled,
                in: RoundedRectangle(cornerRadius: ApplyTheme.R.button, style: .continuous)
            )
    }
}

struct ApplyCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ApplyTheme.C.surface,
                in: RoundedRectangle(cornerRadius: ApplyTheme.R.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ApplyTheme.R.card, style: .continuous)
                    .stroke(ApplyTheme.C.line, lineWidth: 1)
            }
    }
}

extension View {
    func applyCard() -> some View {
        modifier(ApplyCardModifier())
    }
}
