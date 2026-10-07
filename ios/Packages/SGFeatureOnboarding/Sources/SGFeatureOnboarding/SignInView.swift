import SGCore
import SGDesign
import SGModels
import SwiftUI

/// 02 Sign in (presented as a sheet from 01).
public struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let model: OnboardingFlowModel
    private let onFinish: (OnboardingResult) -> Void

    public init() {
        self.init(model: OnboardingFlowModel(isSignInPresented: true), onFinish: { _ in })
    }

    public init(model: OnboardingFlowModel, onFinish: @escaping (OnboardingResult) -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()

            HStack {
                Text("onboarding.sign_in.header".localized(bundle: .module))
                    .font(SG.F.sans(17, .semibold))
                    .foregroundStyle(SG.C.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    model.cancelSignIn()
                    dismiss()
                } label: {
                    Text("onboarding.sign_in.cancel".localized(bundle: .module))
                        .font(SG.F.sans(17, .medium))
                        .foregroundStyle(SG.C.navy)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading)
                .accessibilityIdentifier("onboarding.sign_in.cancel")
            }
            .padding(.horizontal, SG.S.xl)
            .padding(.top, SG.S.s)

            if dynamicTypeSize.isAccessibilitySize {
                scrollContent
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        actions
                            .padding(.horizontal, SG.S.xl)
                            .padding(.bottom, SG.S.s)
                            .frame(maxWidth: .infinity)
                            .background(SG.C.surface)
                    }
            } else {
                scrollContent
                actions
                    .padding(.horizontal, SG.S.xl)
                    .padding(.bottom, SG.S.s)
            }
        }
        .background(SG.C.surface.ignoresSafeArea())
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SG.C.navyTint)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "lock.shield")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(SG.C.navy)
                    )
                    .accessibilityHidden(true)
                    .padding(.top, SG.S.l)

                Text("onboarding.sign_in.title".localized(bundle: .module))
                    .font(SG.F.title)
                    .foregroundStyle(SG.C.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SG.S.l + 4)
                    .accessibilityAddTraits(.isHeader)

                paragraph("onboarding.sign_in.body_1")
                paragraph("onboarding.sign_in.body_2")

                HStack(alignment: .firstTextBaseline, spacing: SG.S.s) {
                    Image(systemName: "info.circle")
                        .accessibilityHidden(true)
                    Text("onboarding.sign_in.demo_note".localized(bundle: .module))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(SG.F.caption)
                .foregroundStyle(SG.C.muted)
                .padding(.top, SG.S.l)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, SG.S.xl)
            .padding(.bottom, SG.S.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func paragraph(_ key: String) -> some View {
        Text(key.localized(bundle: .module))
            .font(SG.F.bodyText)
            .foregroundStyle(SG.C.muted)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, SG.S.m)
    }

    private var actions: some View {
        VStack(spacing: 6) {
            if let error = model.error {
                InlineErrorBanner(
                    message: OnboardingFlowModel.messageKey(for: error).localized(bundle: .module),
                    retry: { Task { await finish(model.retry(session: session)) } }
                )
                .padding(.bottom, SG.S.s)
                .accessibilityIdentifier("onboarding.sign_in.error")
            }

            Button {
                Task { await finish(model.signIn(pivRequired: false, session: session)) }
            } label: {
                accessibilityExpanded(
                    HStack(spacing: SG.S.s) {
                        if model.phase == .loading(pivRequired: false) {
                            ProgressView()
                                .tint(.white)
                            accessibilitySizedLabel("onboarding.sign_in.loading", lineLimit: 2)
                        } else {
                            accessibilitySizedLabel("onboarding.sign_in.continue", lineLimit: 2)
                        }
                    }
                    .frame(minHeight: 54)
                )
            }
            .buttonStyle(PrimaryButton())
            .disabled(model.isLoading)
            .accessibilityIdentifier("onboarding.sign_in.login_gov")

            Button {
                Task { await finish(model.signIn(pivRequired: true, session: session)) }
            } label: {
                accessibilityExpanded(
                    HStack(spacing: SG.S.s) {
                        if model.phase == .loading(pivRequired: true) {
                            ProgressView()
                                .tint(SG.C.navy)
                        }
                        accessibilitySizedLabel("onboarding.sign_in.piv", lineLimit: 3)
                    }
                    .font(SG.F.sans(15, .medium))
                    .foregroundStyle(SG.C.navy)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                )
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading)
            .accessibilityIdentifier("onboarding.sign_in.piv")

            Button {
                if let result = model.continueAsGuest(session: session) {
                    onFinish(result)
                }
            } label: {
                accessibilityExpanded(
                    VStack(spacing: 2) {
                        accessibilitySizedLabel("onboarding.sign_in.guest", lineLimit: 2)
                            .font(SG.F.sans(15, .medium))
                            .foregroundStyle(SG.C.navy)
                        accessibilitySizedLabel("onboarding.sign_in.guest_hint")
                            .font(SG.F.sans(12))
                            .foregroundStyle(SG.C.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                )
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading)
            .accessibilityIdentifier("onboarding.sign_in.guest")
        }
    }

    @ViewBuilder
    private func accessibilitySizedLabel(_ key: String, lineLimit: Int? = nil) -> some View {
        let text = Text(key.localized(bundle: .module))
        if dynamicTypeSize.isAccessibilitySize {
            text
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            text
        }
    }

    @ViewBuilder
    private func accessibilityExpanded<Content: View>(_ content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.fixedSize(horizontal: false, vertical: true)
        } else {
            content
        }
    }

    @MainActor
    private func finish(_ result: OnboardingResult?) {
        if let result {
            onFinish(result)
        }
    }
}

#Preview("Sign in") {
    SignInView()
        .environment(SessionStore(authenticator: PreviewAuthenticator()))
}

#Preview("Sign in · error") {
    SignInView(model: OnboardingFlowModel(isSignInPresented: true, phase: .failed(.offline)), onFinish: { _ in })
        .environment(SessionStore(authenticator: PreviewAuthenticator()))
}
