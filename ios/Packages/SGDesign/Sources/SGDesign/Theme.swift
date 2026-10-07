// Design tokens for the Simpler.Grants.gov iOS app.
// Source of truth: design/GrantsApp.dc.html (README.md → Design Tokens).
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

enum SG {
    enum C {
        static let ink        = Color(hex: 0x14171F)
        static let body       = Color(hex: 0x2A2E38)   // long-form serif text
        static let muted      = Color(hex: 0x5A6070)
        static let subtle     = Color(hex: 0x8A8F99)   // captions, chevrons, placeholders
        static let canvas     = Color(hex: 0xF6F6F3)   // screen background
        static let surface    = Color.white            // cards
        static let field      = Color(hex: 0xEAEAE5)   // search field fill
        static let line       = Color(hex: 0xE4E4DF)   // card borders, separators
        static let lineSoft   = Color(hex: 0xEFEFEA)   // inner row dividers
        static let control    = Color(hex: 0xD5D5D0)   // input / chip borders
        static let navy       = Color(hex: 0x1F3D6E)   // primary
        static let navyPress  = Color(hex: 0x16305A)
        static let navyTint   = Color(hex: 0xE8EDF5)
        static let disabled   = Color(hex: 0xA9B3C4)   // disabled primary button
        static let green      = Color(hex: 0x1E7A4C)
        static let red        = Color(hex: 0xB42318)
        // Status pills (background / foreground)
        static let openBg = Color(hex: 0xE7F3EC), openFg = Color(hex: 0x14583A)
        static let soonBg = Color(hex: 0xFBEDEB), soonFg = Color(hex: 0x8A1C13)
        static let foreBg = Color(hex: 0xFFF3DD), foreFg = Color(hex: 0x7A4A00)
    }

    enum F {
        // Bundle Source Serif 4 (SemiBold 600, Regular 400) and Public Sans (400/500/600/700) — both OFL, Google Fonts.
        // If you prefer native UI type, replace `sans` with .system(size:weight:) — keep the serif.
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
        static let largeTitle  = serif(34)   // tab root titles, line-height 1.1
        static let title       = serif(28)   // detail / sheet titles, 1.15
        static let cardTitle   = serif(18)   // result card titles, 1.25
        static let answer      = serif(17, .regular) // AI answer + summaries, 1.55
        static let section     = sans(20, .semibold)
        static let bodyText    = sans(16)
        static let button      = sans(17, .semibold)
        static let label       = sans(15)
        static let caption     = sans(13)
        static let overline    = sans(12, .semibold) // uppercase, tracking 0.08em
        static let mono        = Font.system(size: 13, weight: .medium, design: .monospaced) // opp numbers, UEI
    }

    enum R { static let card: CGFloat = 18, button: CGFloat = 16, row: CGFloat = 14, input: CGFloat = 12 }
    enum S { static let margin: CGFloat = 20, xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 28 }
}

struct PrimaryButton: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SG.F.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(enabled ? (configuration.isPressed ? SG.C.navyPress : SG.C.navy) : SG.C.disabled,
                        in: RoundedRectangle(cornerRadius: SG.R.button, style: .continuous))
    }
}

struct Chip: View {
    let label: String
    let selected: Bool
    var body: some View {
        Text(label)
            .font(SG.F.sans(14, .medium))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(selected ? .white : SG.C.ink)
            .background(selected ? SG.C.navy : .white, in: Capsule())
            .overlay(Capsule().stroke(selected ? SG.C.navy : SG.C.control, lineWidth: 1))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(SG.S.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SG.C.surface, in: RoundedRectangle(cornerRadius: SG.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SG.R.card, style: .continuous).stroke(SG.C.line, lineWidth: 1))
    }
}
