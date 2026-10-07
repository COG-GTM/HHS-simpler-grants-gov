import Observation
import Foundation
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
        } catch is CancellationError {
            lastError = nil
        } catch let error as GrantsError {
            state = .signedOut
            lastError = error
        } catch {
            state = .signedOut
            lastError = .server(status: 500, message: error.localizedDescription)
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
    }

    public func restore() async {
        let user = await authenticator.restore()
        if let user {
            state = .signedIn(user)
            lastError = nil
        } else if state == .signedOut {
            state = .signedOut
            lastError = nil
        }
    }

    public func handleSessionExpired() {
        state = .signedOut
        lastError = .unauthorized
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
