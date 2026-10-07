import SGCore
import SGModels
import XCTest
@testable import SGFeatureOnboarding

@MainActor
final class OnboardingFlowModelTests: XCTestCase {
    func testSignInSuccessDismissesSheetAndUpdatesSession() async {
        let user = Self.user
        let authenticator = StubAuthenticator(responses: [.success(user)])
        let session = SessionStore(authenticator: authenticator)
        let model = OnboardingFlowModel(isSignInPresented: true)

        let result = await model.signIn(pivRequired: false, session: session)

        XCTAssertEqual(result, .signedIn)
        XCTAssertEqual(model.result, .signedIn)
        XCTAssertFalse(model.isSignInPresented)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(session.state, .signedIn(user))
        let pivRequiredValues = await authenticator.pivRequiredValues
        XCTAssertEqual(pivRequiredValues, [false])
    }

    func testSignInPassesPIVRequirementToAuthenticator() async {
        let authenticator = StubAuthenticator(responses: [.success(Self.user)])
        let session = SessionStore(authenticator: authenticator)
        let model = OnboardingFlowModel(isSignInPresented: true)

        _ = await model.signIn(pivRequired: true, session: session)

        let pivRequiredValues = await authenticator.pivRequiredValues
        XCTAssertEqual(pivRequiredValues, [true])
    }

    func testRetryReusesPIVRequirementAfterUnauthorizedFailure() async {
        let authenticator = StubAuthenticator(responses: [
            .grantsError(.unauthorized),
            .success(Self.user)
        ])
        let session = SessionStore(authenticator: authenticator)
        let model = OnboardingFlowModel(isSignInPresented: true)

        let failedResult = await model.signIn(pivRequired: true, session: session)

        XCTAssertNil(failedResult)
        XCTAssertEqual(model.phase, .failed(.unauthorized))
        XCTAssertNil(model.result)
        XCTAssertTrue(model.isSignInPresented)
        XCTAssertEqual(session.state, .signedOut)

        let retriedResult = await model.retry(session: session)

        XCTAssertEqual(retriedResult, .signedIn)
        let pivRequiredValues = await authenticator.pivRequiredValues
        XCTAssertEqual(pivRequiredValues, [true, true])
    }

    func testNonGrantsErrorUsesServerErrorAndGenericMessageKey() async {
        let authenticator = StubAuthenticator(responses: [.failure])
        let session = SessionStore(authenticator: authenticator)
        let model = OnboardingFlowModel(isSignInPresented: true)

        _ = await model.signIn(pivRequired: false, session: session)

        guard case .server(status: 500, message: _) = session.lastError else {
            return XCTFail("Expected a server error for an unexpected authenticator failure")
        }
        XCTAssertEqual(model.error, session.lastError)
        if let error = model.error {
            XCTAssertEqual(
                OnboardingFlowModel.messageKey(for: error),
                "onboarding.sign_in.error.generic"
            )
        } else {
            XCTFail("Expected a mapped onboarding error")
        }
    }

    func testContinueAsGuestUpdatesSessionAndCompletesFlow() {
        let session = SessionStore(authenticator: StubAuthenticator(responses: []))
        let model = OnboardingFlowModel(isSignInPresented: true)

        let result = model.continueAsGuest(session: session)

        XCTAssertEqual(result, .guest)
        XCTAssertEqual(model.result, .guest)
        XCTAssertFalse(model.isSignInPresented)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(session.state, .guest)
    }

    func testShowAndCancelSignIn() {
        let model = OnboardingFlowModel()

        model.showSignIn()
        XCTAssertTrue(model.isSignInPresented)

        model.cancelSignIn()
        XCTAssertFalse(model.isSignInPresented)
        XCTAssertEqual(model.phase, .idle)
    }

    func testMessageKeyMapsAuthenticationErrors() {
        XCTAssertEqual(
            OnboardingFlowModel.messageKey(for: .unauthorized),
            "onboarding.sign_in.error.unauthorized"
        )
        XCTAssertEqual(
            OnboardingFlowModel.messageKey(for: .offline),
            "onboarding.sign_in.error.offline"
        )
        XCTAssertEqual(
            OnboardingFlowModel.messageKey(for: .notFound),
            "onboarding.sign_in.error.generic"
        )
        XCTAssertEqual(
            OnboardingFlowModel.messageKey(for: .server(status: 500, message: nil)),
            "onboarding.sign_in.error.generic"
        )
        XCTAssertEqual(
            OnboardingFlowModel.messageKey(for: .decoding("invalid")),
            "onboarding.sign_in.error.generic"
        )
    }

    private static let user = UserProfile(
        userId: "sample-dana",
        email: "dana.reyes@example.org",
        firstName: "Dana",
        lastName: "Reyes"
    )
}

private actor StubAuthenticator: Authenticating {
    enum Response: Sendable {
        case success(UserProfile)
        case grantsError(GrantsError)
        case failure
    }

    private var responses: [Response]
    private(set) var pivRequiredValues: [Bool] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func signIn(pivRequired: Bool) async throws -> UserProfile {
        pivRequiredValues.append(pivRequired)
        guard !responses.isEmpty else {
            throw StubError.unexpectedSignIn
        }
        switch responses.removeFirst() {
        case let .success(user):
            return user
        case let .grantsError(error):
            throw error
        case .failure:
            throw StubError.unexpectedSignIn
        }
    }

    func restore() async -> UserProfile? { nil }

    func signOut() async {}
}

private enum StubError: Error {
    case unexpectedSignIn
}
