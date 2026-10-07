import SwiftUI

public struct DemoBanner: View {
    public init() {}

    public var body: some View {
        Text("design.demo_banner".localized(bundle: .module))
            .font(SG.F.sans(12, .medium))
            .foregroundStyle(SG.C.muted)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.horizontal, SG.S.margin)
            .background(SG.C.navyTint)
            .accessibilityAddTraits(.isStaticText)
    }
}
