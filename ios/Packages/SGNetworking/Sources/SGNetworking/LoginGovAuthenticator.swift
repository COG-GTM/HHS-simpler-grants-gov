import SGModels

public struct LoginGovAuthenticator: Authenticating {
    private let dataSource: any GrantsDataSource
    private let testToken: String?

    public init(dataSource: any GrantsDataSource, testToken: String? = nil) {
        self.dataSource = dataSource
        self.testToken = testToken
    }

    public func signIn(pivRequired: Bool) async throws -> UserProfile {
        throw GrantsError.server(status: 501, message: "not implemented")
    }

    public func restore() async -> UserProfile? {
        guard let testToken, !testToken.isEmpty else {
            return nil
        }
        return try? await dataSource.currentUser()
    }

    public func signOut() async {}
}
