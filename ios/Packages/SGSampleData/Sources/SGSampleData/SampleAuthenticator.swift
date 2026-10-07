import SGModels

public struct SampleAuthenticator: Authenticating {
    private let preview: PreviewAuthenticator

    public init() {
        preview = PreviewAuthenticator()
    }

    public func signIn(pivRequired: Bool) async throws -> UserProfile {
        try await preview.signIn(pivRequired: pivRequired)
    }

    public func restore() async -> UserProfile? {
        await preview.restore()
    }

    public func signOut() async {
        await preview.signOut()
    }
}
