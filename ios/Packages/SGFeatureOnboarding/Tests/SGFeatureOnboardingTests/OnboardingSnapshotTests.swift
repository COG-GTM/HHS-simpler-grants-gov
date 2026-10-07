#if canImport(UIKit)
import SGCore
import SGDesign
import SGFeatureOnboarding
import SGModels
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@MainActor
final class OnboardingSnapshotTests: XCTestCase {
    private static var fontsRegistered = false
    private static let recordSnapshots = false

    override func setUp() {
        super.setUp()
        guard !Self.fontsRegistered else { return }
        SGFonts.registerAll()
        Self.fontsRegistered = true
    }

    func testWelcome() {
        assertView(WelcomeView(), named: "welcome")
    }

    func testSignInIdle() {
        let view = SignInView(
            model: OnboardingFlowModel(isSignInPresented: true),
            onFinish: { _ in }
        )
        .environment(SessionStore(authenticator: PreviewAuthenticator()))
        assertView(view, named: "sign-in-idle")
    }

    func testSignInLoading() {
        let model = OnboardingFlowModel(
            isSignInPresented: true,
            phase: .loading(pivRequired: false)
        )
        let view = SignInView(model: model, onFinish: { _ in })
            .environment(SessionStore(authenticator: PreviewAuthenticator()))
        assertView(view, named: "sign-in-loading")
    }

    func testSignInError() {
        let model = OnboardingFlowModel(
            isSignInPresented: true,
            phase: .failed(.unauthorized)
        )
        let view = SignInView(model: model, onFinish: { _ in })
            .environment(SessionStore(authenticator: PreviewAuthenticator()))
        assertView(view, named: "sign-in-error")
    }

    func testSignInIdleAtXXXL() {
        let view = SignInView(
            model: OnboardingFlowModel(isSignInPresented: true),
            onFinish: { _ in }
        )
        .environment(SessionStore(authenticator: PreviewAuthenticator()))
        let traits = UITraitCollection(
            preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        assertView(view, named: "sign-in-idle-xxxl", traits: traits)
    }

    private func assertView<Content: View>(
        _ content: Content,
        named: String,
        traits: UITraitCollection? = nil
    ) {
        let controller = UIHostingController(rootView: content)
        let snapshotting: Snapshotting<UIViewController, UIImage>
        if let traits {
            snapshotting = .image(on: .iPhone13, traits: traits)
        } else {
            snapshotting = .image(on: .iPhone13)
        }
        if Self.recordSnapshots {
            _ = verifySnapshot(of: controller, as: snapshotting, named: named, record: true)
        } else {
            assertSnapshot(of: controller, as: snapshotting, named: named, record: false)
        }
    }
}
#endif
