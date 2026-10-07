import SwiftUI

public struct SGNavBar: View {
    @Environment(\.dismiss) private var dismiss

    private let backLabel: String
    private let title: String
    private let trailingAction: String?
    private let onBack: (() -> Void)?
    private let onTrailing: (() -> Void)?

    public init(
        backLabel: String,
        title: String,
        trailingAction: String? = nil,
        onBack: (() -> Void)? = nil,
        onTrailing: (() -> Void)? = nil
    ) {
        self.backLabel = backLabel
        self.title = title
        self.trailingAction = trailingAction
        self.onBack = onBack
        self.onTrailing = onTrailing
    }

    public var body: some View {
        HStack(spacing: SG.S.s) {
            Button {
                if let onBack {
                    onBack()
                } else {
                    dismiss()
                }
            } label: {
                HStack(spacing: SG.S.xs) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text(backLabel)
                }
                .font(SG.F.sans(15, .medium))
                .foregroundStyle(SG.C.navy)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backLabel)

            Spacer(minLength: SG.S.s)

            Text(title)
                .font(SG.F.sans(17, .semibold))
                .foregroundStyle(SG.C.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: SG.S.s)

            if let trailingAction {
                Button(trailingAction) {
                    onTrailing?()
                }
                .font(SG.F.sans(15, .medium))
                .foregroundStyle(SG.C.navy)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
    }
}
