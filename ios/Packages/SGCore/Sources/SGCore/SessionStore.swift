import Observation
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

    private let authenticator: any Authenticating

    public init(authenticator: any Authenticating) {
        self.authenticator = authenticator
    }

    public func signIn(pivRequired: Bool) async {
        do {
            let user = try await authenticator.signIn(pivRequired: pivRequired)
            state = .signedIn(user)
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
        if let user = await authenticator.restore() {
            state = .signedIn(user)
        } else {
            state = .signedOut
        }
        lastError = nil
    }
}
