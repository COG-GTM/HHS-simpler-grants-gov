import SwiftUI

public struct StatusChip: View {
    private let status: String

    public init(status: String) {
        self.status = status
    }

    private var style: (label: String, foreground: Color, background: Color) {
        switch status.lowercased() {
        case "open", "posted":
            return ("design.status.open".localized(bundle: .module), SG.C.openFg, SG.C.openBg)
        case "closing soon", "closing_soon":
            return ("design.status.closing_soon".localized(bundle: .module), SG.C.soonFg, SG.C.soonBg)
        case "forecasted":
            return ("design.status.forecasted".localized(bundle: .module), SG.C.foreFg, SG.C.foreBg)
        case "closed", "archived":
            return ("design.status.closed".localized(bundle: .module), SG.C.muted, SG.C.field)
        default:
            return (status, SG.C.muted, SG.C.field)
        }
    }

    public var body: some View {
        Text(style.label)
            .font(SG.F.sans(12, .semibold))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, SG.S.m)
            .frame(minHeight: 32)
            .background(style.background, in: Capsule())
            .accessibilityLabel(style.label)
    }
}
