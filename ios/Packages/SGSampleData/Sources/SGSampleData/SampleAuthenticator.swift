import Foundation
import SGModels

public struct SampleAuthenticator: Authenticating {
    private let store: SampleAuthStore
    private let normalSignInDelay: Duration
    private let pivSignInDelay: Duration

    public init(
        normalSignInDelay: Duration = .zero,
        pivSignInDelay: Duration = .milliseconds(400)
    ) {
        store = SampleAuthStore()
        self.normalSignInDelay = normalSignInDelay
        self.pivSignInDelay = pivSignInDelay
    }

    public func signIn(pivRequired: Bool) async throws -> UserProfile {
        let delay = pivRequired ? pivSignInDelay : normalSignInDelay
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return await store.signIn()
    }

    public func restore() async -> UserProfile? {
        await store.restore()
    }

    public func signOut() async {
        await store.signOut()
    }
}

actor SampleAuthStore {
    private var signedIn = false

    func signIn() -> UserProfile {
        signedIn = true
        return SampleUser.profile
    }

    func restore() -> UserProfile? {
        signedIn ? SampleUser.profile : nil
    }

    func signOut() {
        signedIn = false
    }
}

enum SampleUser {
    static let profile = UserProfile(
        userId: "sample-dana-reyes",
        email: "dana.reyes@bluefieldchc.example",
        firstName: "Dana",
        lastName: "Reyes"
    )
}
