import SGCore
import SGModels
import SwiftUI

/// Wires 01 Welcome → 02 Sign in → finish.
public struct OnboardingFlowView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = OnboardingFlowModel()

    private let onFinish: (OnboardingResult) -> Void

    public init(onFinish: @escaping (OnboardingResult) -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        @Bindable var model = model
        WelcomeView(
            onSignIn: { model.showSignIn() },
            onContinueAsGuest: {
                if let result = model.continueAsGuest(session: session) {
                    onFinish(result)
                }
            }
        )
        .sheet(isPresented: $model.isSignInPresented) {
            SignInView(model: model, onFinish: onFinish)
                .presentationDetents([.large])
                .interactiveDismissDisabled(model.isLoading)
        }
    }
}

#Preview("Onboarding flow") {
    OnboardingFlowView(onFinish: { _ in })
        .environment(SessionStore(authenticator: PreviewAuthenticator()))
}
