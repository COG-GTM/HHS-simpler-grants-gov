import SGModels

public struct SampleDataSource: GrantsDataSource {
    private let preview: PreviewDataSource

    public init() {
        preview = PreviewDataSource()
    }

    public func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        try await preview.searchOpportunities(request)
    }

    public func opportunity(id: String) async throws -> OpportunityDetail {
        try await preview.opportunity(id: id)
    }

    public func currentUser() async throws -> UserProfile {
        try await preview.currentUser()
    }

    public func organizations() async throws -> [Organization] {
        try await preview.organizations()
    }

    public func applications() async throws -> [ApplicationSummary] {
        try await preview.applications()
    }

    public func startApplication(
        competitionId: String,
        name: String,
        organizationId: String?
    ) async throws -> String {
        try await preview.startApplication(
            competitionId: competitionId,
            name: name,
            organizationId: organizationId
        )
    }

    public func application(id: String) async throws -> Application {
        try await preview.application(id: id)
    }

    public func form(id: String) async throws -> FormDefinition {
        try await preview.form(id: id)
    }

    public func saveForm(
        applicationId: String,
        formId: String,
        response: JSONValue
    ) async throws -> FormSaveResult {
        try await preview.saveForm(
            applicationId: applicationId,
            formId: formId,
            response: response
        )
    }

    public func submit(applicationId: String) async throws -> SubmissionResult {
        try await preview.submit(applicationId: applicationId)
    }

    public func savedOpportunityIds() async throws -> Set<String> {
        try await preview.savedOpportunityIds()
    }

    public func setSaved(_ saved: Bool, opportunityId: String) async throws {
        try await preview.setSaved(saved, opportunityId: opportunityId)
    }
}
