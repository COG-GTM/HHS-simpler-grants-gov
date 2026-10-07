import SwiftUI

public struct EmptyStateView: View {
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: SG.S.m) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(SG.C.muted)
                .accessibilityHidden(true)

            Text(title)
                .font(SG.F.section)
                .foregroundStyle(SG.C.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(SG.F.bodyText)
                .foregroundStyle(SG.C.muted)
                .multilineTextAlignment(.center)

            if let action {
                Button(actionTitle ?? "design.empty.action".localized(bundle: .module), action: action)
                    .font(SG.F.sans(15, .semibold))
                    .foregroundStyle(SG.C.navy)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SG.S.xl)
    }
}
