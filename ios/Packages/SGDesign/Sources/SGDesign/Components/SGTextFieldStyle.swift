import SwiftUI

public struct SGTextFieldStyle: TextFieldStyle {
    public init() {}

    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(SG.F.bodyText)
            .foregroundStyle(SG.C.ink)
            .padding(.horizontal, SG.S.m)
            .frame(minHeight: 48)
            .background(SG.C.surface, in: RoundedRectangle(cornerRadius: SG.R.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SG.R.input, style: .continuous)
                    .stroke(SG.C.control, lineWidth: 1)
            )
    }
}
