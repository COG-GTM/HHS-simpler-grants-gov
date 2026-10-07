import Foundation
import SGModels

public struct LiveDataSource: GrantsDataSource {
    public let baseURL: URL
    public let apiKey: String?
    public let token: String?

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:8080")!,
        apiKey: String? = "local-dev-api-key",
        token: String? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.token = token
    }

    public func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        throw notImplemented
    }

    public func opportunity(id: String) async throws -> OpportunityDetail {
        throw notImplemented
    }

    public func currentUser() async throws -> UserProfile {
        throw notImplemented
    }

    public func organizations() async throws -> [Organization] {
        throw notImplemented
    }

    public func applications() async throws -> [ApplicationSummary] {
        throw notImplemented
    }

    public func startApplication(
        competitionId: String,
        name: String,
        organizationId: String?
    ) async throws -> String {
        throw notImplemented
    }

    public func application(id: String) async throws -> Application {
        throw notImplemented
    }

    public func form(id: String) async throws -> FormDefinition {
        throw notImplemented
    }

    public func saveForm(
        applicationId: String,
        formId: String,
        response: JSONValue
    ) async throws -> FormSaveResult {
        throw notImplemented
    }

    public func submit(applicationId: String) async throws -> SubmissionResult {
        throw notImplemented
    }

    public func savedOpportunityIds() async throws -> Set<String> {
        throw notImplemented
    }

    public func setSaved(_ saved: Bool, opportunityId: String) async throws {
        throw notImplemented
    }

    private var notImplemented: GrantsError {
        .server(status: 501, message: "not implemented")
    }
}
