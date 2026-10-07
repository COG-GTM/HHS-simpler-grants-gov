import Foundation
import SGModels
import XCTest
@testable import SGFeatureProfile

@MainActor
final class ProfileModelTests: XCTestCase {
    func testLoadIsKeyedByUserResetClearsStateAndFailureCanRetry() async {
        let model = ProfileModel()
        let dataSource = ProfileModelTestDataSource()

        await model.load(from: dataSource, userId: "user-A")
        XCTAssertEqual(model.loadedUserId, "user-A")
        XCTAssertTrue(model.isLoaded)
        XCTAssertNotNil(model.organization)
        XCTAssertFalse(model.savedOpportunityIds.isEmpty)
        XCTAssertFalse(model.savedOpportunities.isEmpty)

        model.reset()
        XCTAssertNil(model.organization)
        XCTAssertTrue(model.savedOpportunityIds.isEmpty)
        XCTAssertTrue(model.savedOpportunities.isEmpty)
        XCTAssertNil(model.loadError)
        XCTAssertNil(model.loadedUserId)
        XCTAssertFalse(model.isLoaded)
        XCTAssertFalse(model.isLoading)

        await model.load(from: ProfileModelTestDataSource(failOrganizations: true), userId: "user-B")
        XCTAssertNil(model.organization)
        XCTAssertFalse(model.savedOpportunityIds.isEmpty)
        XCTAssertFalse(model.savedOpportunities.isEmpty)
        XCTAssertNotNil(model.loadError)
        XCTAssertNil(model.loadedUserId)
        XCTAssertFalse(model.isLoaded)

        await model.load(from: dataSource, userId: "user-B")
        XCTAssertNil(model.loadError)
        XCTAssertEqual(model.loadedUserId, "user-B")
        XCTAssertTrue(model.isLoaded)
    }

    func testSavedOpportunityFailureRetainsOrganizationAndLeavesSavedDataEmpty() async {
        let model = ProfileModel()
        let dataSource = ProfileModelTestDataSource(failSavedOpportunityIds: true)

        await model.load(from: dataSource, userId: "user-A")
        XCTAssertNotNil(model.organization)
        XCTAssertTrue(model.savedOpportunityIds.isEmpty)
        XCTAssertTrue(model.savedOpportunities.isEmpty)
        XCTAssertNotNil(model.loadError)
        XCTAssertNil(model.loadedUserId)
        XCTAssertFalse(model.isLoaded)
    }
}

private struct ProfileModelTestDataSource: GrantsDataSource {
    private let base = PreviewDataSource()
    private let failOrganizations: Bool
    private let failSavedOpportunityIds: Bool

    init(failOrganizations: Bool = false, failSavedOpportunityIds: Bool = false) {
        self.failOrganizations = failOrganizations
        self.failSavedOpportunityIds = failSavedOpportunityIds
    }

    func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        try await base.searchOpportunities(request)
    }

    func opportunity(id: String) async throws -> OpportunityDetail {
        try await base.opportunity(id: id)
    }

    func currentUser() async throws -> UserProfile {
        try await base.currentUser()
    }

    func organizations() async throws -> [Organization] {
        if failOrganizations {
            throw GrantsError.offline
        }
        return try await base.organizations()
    }

    func applications() async throws -> [ApplicationSummary] {
        try await base.applications()
    }

    func startApplication(
        competitionId: String,
        name: String,
        organizationId: String?
    ) async throws -> String {
        try await base.startApplication(
            competitionId: competitionId,
            name: name,
            organizationId: organizationId
        )
    }

    func application(id: String) async throws -> Application {
        try await base.application(id: id)
    }

    func form(id: String) async throws -> FormDefinition {
        try await base.form(id: id)
    }

    func saveForm(
        applicationId: String,
        formId: String,
        response: JSONValue
    ) async throws -> FormSaveResult {
        try await base.saveForm(
            applicationId: applicationId,
            formId: formId,
            response: response
        )
    }

    func submit(applicationId: String) async throws -> SubmissionResult {
        try await base.submit(applicationId: applicationId)
    }

    func savedOpportunityIds() async throws -> Set<String> {
        if failSavedOpportunityIds {
            throw GrantsError.offline
        }
        return try await base.savedOpportunityIds()
    }

    func setSaved(_ saved: Bool, opportunityId: String) async throws {
        try await base.setSaved(saved, opportunityId: opportunityId)
    }
}
