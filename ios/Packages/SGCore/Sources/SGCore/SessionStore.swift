import Observation
import Foundation
import os
import SGModels

public enum SessionState: Sendable, Equatable {
    case signedOut
    case guest
    case signedIn(UserProfile)
}

@Observable
@MainActor
public final class SessionStore {
    public private(set) var state: SessionState = .signedOut
    public private(set) var lastError: GrantsError?
    public private(set) var isBusy = false

    private let authenticator: any Authenticating
    private let logger = Logger(subsystem: "ai.cognition.demo.simplergrants", category: "session")
    private var sessionExpiredObserver: SessionExpiredObserver?

    public init(authenticator: any Authenticating) {
        self.authenticator = authenticator
        sessionExpiredObserver = SessionExpiredObserver(
            NotificationCenter.default.addObserver(
                forName: .sgSessionExpired,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleSessionExpired() }
            }
        )
    }

    public func signIn(pivRequired: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let user = try await authenticator.signIn(pivRequired: pivRequired)
            state = .signedIn(user)
            lastError = nil
            logger.info("sign-in succeeded")
        } catch is CancellationError {
            lastError = nil
            logger.info("sign-in cancelled")
        } catch let error as GrantsError {
            state = .signedOut
            lastError = error
            logger.error("sign-in failed: \(Self.errorCaseName(for: error), privacy: .public)")
        } catch {
            state = .signedOut
            lastError = .server(status: 500, message: error.localizedDescription)
            logger.error("sign-in failed: server")
        }
    }

    public func continueAsGuest() {
        state = .guest
        lastError = nil
    }

    public func signOut() async {
        await authenticator.signOut()
        state = .signedOut
        lastError = nil
        logger.info("signed out")
    }

    public func restore() async {
        let user = await authenticator.restore()
        if let user {
            state = .signedIn(user)
            lastError = nil
            logger.info("session restored: signedIn")
        } else if state == .signedOut {
            state = .signedOut
            lastError = nil
            logger.info("session restored: signedOut")
        }
    }

    public func handleSessionExpired() {
        state = .signedOut
        lastError = .unauthorized
        logger.info("session expired")
    }

    private static func errorCaseName(for error: GrantsError) -> String {
        switch error {
        case .unauthorized:
            return "unauthorized"
        case .notFound:
            return "notFound"
        case .offline:
            return "offline"
        case .server(_, _):
            return "server"
        case .decoding(_):
            return "decoding"
        }
    }
}

private final class SessionExpiredObserver {
    private let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
