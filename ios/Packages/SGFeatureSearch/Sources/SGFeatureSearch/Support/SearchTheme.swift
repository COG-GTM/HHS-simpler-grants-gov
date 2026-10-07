import SwiftUI

// Mirror of SGDesign Theme.swift tokens (internal in SGDesign). Replace with SG.* once SGDesign exports them.
enum SearchTheme {
    enum C {
        static let ink = Color(hex: 0x14171F)
        static let body = Color(hex: 0x2A2E38)
        static let muted = Color(hex: 0x5A6070)
        static let subtle = Color(hex: 0x8A8F99)
        static let canvas = Color(hex: 0xF6F6F3)
        static let surface = Color.white
        static let field = Color(hex: 0xEAEAE5)
        static let line = Color(hex: 0xE4E4DF)
        static let lineSoft = Color(hex: 0xEFEFEA)
        static let control = Color(hex: 0xD5D5D0)
        static let navy = Color(hex: 0x1F3D6E)
        static let navyPress = Color(hex: 0x16305A)
        static let navyTint = Color(hex: 0xE8EDF5)
        static let disabled = Color(hex: 0xA9B3C4)
        static let green = Color(hex: 0x1E7A4C)
        static let red = Color(hex: 0xB42318)
        static let openBg = Color(hex: 0xE7F3EC)
        static let openFg = Color(hex: 0x14583A)
        static let soonBg = Color(hex: 0xFBEDEB)
        static let soonFg = Color(hex: 0x8A1C13)
        static let foreBg = Color(hex: 0xFFF3DD)
        static let foreFg = Color(hex: 0x7A4A00)
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
        static let title = serif(28)
        static let cardTitle = serif(18)
        static let answer = serif(17, .regular)
        static let section = sans(20, .semibold)
        static let bodyText = sans(16)
        static let button = sans(17, .semibold)
        static let label = sans(15)
        static let caption = sans(13)
        static let overline = sans(12, .semibold)
        static let mono = Font.custom("Menlo", size: 13, relativeTo: .caption)

        static func monoFont(_ size: CGFloat, _ weight: Font.Weight, relativeTo textStyle: Font.TextStyle) -> Font {
            .custom("Menlo", size: size, relativeTo: textStyle)
        }
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

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct SearchPrimaryButtonStyle: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SearchTheme.F.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                enabled ? (configuration.isPressed ? SearchTheme.C.navyPress : SearchTheme.C.navy) : SearchTheme.C.disabled,
                in: RoundedRectangle(cornerRadius: SearchTheme.R.button, style: .continuous)
            )
    }
}

struct SearchChip: View {
    let label: String
    let selected: Bool

    var body: some View {
        Text(label)
            .font(SearchTheme.F.sans(14, .medium))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .foregroundStyle(selected ? .white : SearchTheme.C.ink)
            .background(selected ? SearchTheme.C.navy : .white, in: Capsule())
            .overlay(Capsule().stroke(selected ? SearchTheme.C.navy : SearchTheme.C.control, lineWidth: 1))
    }
}

struct SearchCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(SearchTheme.S.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                SearchTheme.C.surface,
                in: RoundedRectangle(cornerRadius: SearchTheme.R.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SearchTheme.R.card, style: .continuous)
                    .stroke(SearchTheme.C.line, lineWidth: 1)
            )
    }
}
