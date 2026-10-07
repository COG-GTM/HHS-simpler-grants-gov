import SGDesign
import SwiftUI

public enum OnboardingResult: Sendable, Hashable {
    case signedIn
    case guest
}

private struct FeatureStubScreen: View {
    let titleKey: String

    var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            VStack(spacing: 16) {
                Text(titleKey.localized(bundle: .module))
                    .font(.largeTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("onboarding.coming_soon".localized(bundle: .module))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }
}

public struct OnboardingFlowView: View {
    private let onFinish: (OnboardingResult) -> Void

    public init(onFinish: @escaping (OnboardingResult) -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        FeatureStubScreen(titleKey: "onboarding.flow.title")
    }
}

public struct WelcomeView: View {
    public init() {}

    public var body: some View {
        FeatureStubScreen(titleKey: "onboarding.welcome.title")
    }
}

public struct SignInView: View {
    public init() {}

    public var body: some View {
        FeatureStubScreen(titleKey: "onboarding.sign_in.title")
    }
}

#Preview("Onboarding flow") {
    OnboardingFlowView(onFinish: { _ in })
}

#Preview("Welcome") {
    WelcomeView()
}

#Preview("Sign in") {
    SignInView()
}
