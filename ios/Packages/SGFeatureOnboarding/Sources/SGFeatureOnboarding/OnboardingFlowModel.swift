import Foundation
import Observation
import SGCore
import SGModels

public enum OnboardingResult: Sendable, Hashable {
    case signedIn
    case guest
}

/// State machine for 01 Welcome → 02 Sign in → finish.
@Observable
@MainActor
public final class OnboardingFlowModel {
    public enum Phase: Sendable, Equatable {
        case idle
        case loading(pivRequired: Bool)
        case failed(GrantsError)
    }

    public var isSignInPresented: Bool
    public private(set) var phase: Phase
    public private(set) var result: OnboardingResult?
    private var lastPivRequired = false

    public init(isSignInPresented: Bool = false, phase: Phase = .idle) {
        self.isSignInPresented = isSignInPresented
        self.phase = phase
        if case let .loading(pivRequired) = phase {
            lastPivRequired = pivRequired
        }
    }

    public var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    public var error: GrantsError? {
        if case let .failed(error) = phase { return error }
        return nil
    }

    public func showSignIn() {
        guard result == nil else { return }
        phase = .idle
        isSignInPresented = true
    }

    public func cancelSignIn() {
        guard !isLoading else { return }
        phase = .idle
        isSignInPresented = false
    }

    /// Signs in through the session store. Returns `.signedIn` on success, `nil` on failure or when
    /// a sign-in is already running.
    @discardableResult
    public func signIn(pivRequired: Bool, session: SessionStore) async -> OnboardingResult? {
        guard !isLoading, result == nil else { return nil }
        lastPivRequired = pivRequired
        phase = .loading(pivRequired: pivRequired)
        await session.signIn(pivRequired: pivRequired)
        if case .signedIn = session.state {
            phase = .idle
            isSignInPresented = false
            result = .signedIn
            return .signedIn
        }
        phase = .failed(session.lastError ?? .unauthorized)
        return nil
    }

    @discardableResult
    public func retry(session: SessionStore) async -> OnboardingResult? {
        await signIn(pivRequired: lastPivRequired, session: session)
    }

    @discardableResult
    public func continueAsGuest(session: SessionStore) -> OnboardingResult? {
        guard !isLoading, result == nil else { return nil }
        session.continueAsGuest()
        phase = .idle
        isSignInPresented = false
        result = .guest
        return .guest
    }

    public static func messageKey(for error: GrantsError) -> String {
        switch error {
        case .unauthorized:
            return "onboarding.sign_in.error.unauthorized"
        case .offline:
            return "onboarding.sign_in.error.offline"
        case .notFound, .server, .decoding:
            return "onboarding.sign_in.error.generic"
        }
    }
}
