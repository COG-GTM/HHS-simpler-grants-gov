import SGDesign
import SwiftUI

/// 01 Welcome.
public struct WelcomeView: View {
    private let onSignIn: () -> Void
    private let onContinueAsGuest: () -> Void

    public init(onSignIn: @escaping () -> Void = {}, onContinueAsGuest: @escaping () -> Void = {}) {
        self.onSignIn = onSignIn
        self.onContinueAsGuest = onContinueAsGuest
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: SG.S.s) {
                        Image(systemName: "info.circle")
                            .font(SG.F.sans(12, .medium))
                            .accessibilityHidden(true)
                        Text("onboarding.welcome.disclaimer".localized(bundle: .module))
                            .font(SG.F.sans(12))
                    }
                    .foregroundStyle(SG.C.muted)
                    .padding(.top, SG.S.xs)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("onboarding.welcome.disclaimer")

                    WelcomeHero()
                        .padding(.top, SG.S.xl)

                    Text("onboarding.welcome.overline".localized(bundle: .module))
                        .font(SG.F.overline)
                        .tracking(0.08 * 12)
                        .foregroundStyle(SG.C.navy)
                        .padding(.top, SG.S.xxl)

                    Text("onboarding.welcome.heading".localized(bundle: .module))
                        .font(SG.F.largeTitle)
                        .foregroundStyle(SG.C.ink)
                        .lineSpacing(-2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .accessibilityAddTraits(.isHeader)

                    Text("onboarding.welcome.body".localized(bundle: .module))
                        .font(SG.F.bodyText)
                        .foregroundStyle(SG.C.muted)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
                .padding(.horizontal, SG.S.xl)
                .padding(.bottom, SG.S.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 6) {
                PageDots()
                    .padding(.bottom, 14)

                Button(action: onSignIn) {
                    Text("onboarding.welcome.sign_in".localized(bundle: .module))
                        .frame(minHeight: 54)
                }
                .buttonStyle(PrimaryButton())
                .accessibilityIdentifier("onboarding.welcome.sign_in")

                Button(action: onContinueAsGuest) {
                    Text("onboarding.welcome.guest".localized(bundle: .module))
                        .font(SG.F.sans(16, .semibold))
                        .foregroundStyle(SG.C.navy)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.welcome.guest")
            }
            .padding(.horizontal, SG.S.xl)
            .padding(.bottom, SG.S.s)
        }
        .background(SG.C.canvas.ignoresSafeArea())
    }
}

private struct WelcomeHero: View {
    var body: some View {
        ZStack {
            Canvas { context, size in
                let stripe: CGFloat = 10
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.934)))
                var x: CGFloat = -size.height
                var index = 0
                while x < size.width + size.height {
                    if index.isMultiple(of: 2) {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + stripe * 1.414, y: 0))
                        path.addLine(to: CGPoint(x: x + stripe * 1.414 + size.height, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                        path.closeSubpath()
                        context.fill(path, with: .color(Color(red: 0.914, green: 0.910, blue: 0.886)))
                    }
                    x += stripe * 1.414
                    index += 1
                }
            }

            Image(systemName: "building.columns.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(SG.C.navy.opacity(0.22))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct PageDots: View {
    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(SG.C.navy).frame(width: 18, height: 6)
            Capsule().fill(SG.C.control).frame(width: 6, height: 6)
            Capsule().fill(SG.C.control).frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

#Preview("Welcome") {
    WelcomeView()
}
