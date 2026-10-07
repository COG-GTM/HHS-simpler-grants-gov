import Foundation

public protocol GrantsDataSource: Sendable {
    func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse
    func opportunity(id: String) async throws -> OpportunityDetail
    func currentUser() async throws -> UserProfile
    func organizations() async throws -> [Organization]
    func applications() async throws -> [ApplicationSummary]
    func startApplication(competitionId: String, name: String, organizationId: String?) async throws -> String
    func application(id: String) async throws -> Application
    func form(id: String) async throws -> FormDefinition
    func saveForm(applicationId: String, formId: String, response: JSONValue) async throws -> FormSaveResult
    func submit(applicationId: String) async throws -> SubmissionResult
    func savedOpportunityIds() async throws -> Set<String>
    func setSaved(_ saved: Bool, opportunityId: String) async throws
}
