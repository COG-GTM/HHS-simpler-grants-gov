import SwiftUI

public struct GovStyleHeader: View {
    private let initials: String
    private let onProfile: () -> Void

    public init(initials: String = "DR", onProfile: @escaping () -> Void = {}) {
        self.initials = initials
        self.onProfile = onProfile
    }

    public var body: some View {
        HStack {
            Text("design.header.wordmark".localized(bundle: .module))
                .font(SG.F.overline)
                .tracking(0.08 * 12)
                .foregroundStyle(SG.C.navy)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button(action: onProfile) {
                Text(initials)
                    .font(SG.F.sans(13, .semibold))
                    .foregroundStyle(SG.C.navy)
                    .frame(width: 40, height: 40)
                    .background(SG.C.navyTint, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("design.header.profile_accessibility".localized(bundle: .module))
        }
        .frame(minHeight: 44)
    }
}
