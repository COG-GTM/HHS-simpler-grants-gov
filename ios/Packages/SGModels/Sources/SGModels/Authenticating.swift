import Foundation

public protocol Authenticating: Sendable {
    func signIn(pivRequired: Bool) async throws -> UserProfile
    func restore() async -> UserProfile?
    func signOut() async
}

public struct PreviewAuthenticator: Authenticating {
    public init() {}

    public func signIn(pivRequired: Bool) async throws -> UserProfile {
        try await Task.sleep(for: .milliseconds(300))
        return UserProfile(
            userId: "sample-dana-reyes",
            email: "dana.reyes@example.org",
            firstName: "Dana",
            lastName: "Reyes"
        )
    }

    public func restore() async -> UserProfile? {
        nil
    }

    public func signOut() async {}
}
