import SwiftUI

public struct SecondaryButton: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SG.F.button)
            .foregroundStyle(SG.C.navy)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                configuration.isPressed ? SG.C.navyTint : SG.C.surface,
                in: RoundedRectangle(cornerRadius: SG.R.button, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SG.R.button, style: .continuous)
                    .stroke(SG.C.control, lineWidth: 1)
            )
    }
}
