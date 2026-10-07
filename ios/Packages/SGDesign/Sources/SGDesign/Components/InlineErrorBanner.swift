import SwiftUI

public struct InlineErrorBanner: View {
    private let message: String
    private let retry: (() -> Void)?

    public init(message: String, retry: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        HStack(alignment: .top, spacing: SG.S.s) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(SG.C.red)
                .accessibilityHidden(true)

            Text(message)
                .font(SG.F.bodyText)
                .foregroundStyle(SG.C.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let retry {
                Button("design.error.retry".localized(bundle: .module), action: retry)
                    .font(SG.F.sans(14, .semibold))
                    .foregroundStyle(SG.C.navy)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
            }
        }
        .padding(SG.S.m)
        .background(SG.C.soonBg, in: RoundedRectangle(cornerRadius: SG.R.row, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
