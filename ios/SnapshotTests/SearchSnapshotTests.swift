import SGCore
import SGDesign
import SGFeatureSearch
import SGModels
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SearchSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_331_200)

    override func setUp() {
        super.setUp()
        SGFonts.registerAll()
    }

    func testSearchHome() {
        let store = RecentSearchStore(
            defaults: UserDefaults(suiteName: "search-snapshot-\(UUID().uuidString)")!
        )
        store.record("community health")
        store.updateCount(186, for: "community health")
        store.record("rural clinics")
        store.updateCount(42, for: "rural clinics")
        store.record("climate planning")
        store.updateCount(17, for: "climate planning")
        let view = SearchHomeView(recentStore: store)
            .environment(AppRouter())
            .environment(\.grantsDataSource, PreviewDataSource())
        assertImage(view, named: "search-home")
    }

    func testResultsLoaded() async {
        let source = PreviewDataSource()
        let model = ResultsViewModel(
            request: SearchRequest(),
            dataSource: source,
            now: now
        )
        await model.load()
        let view = ResultsView(viewModel: model)
            .environment(AppRouter())
            .environment(\.grantsDataSource, source)
        assertImage(view, named: "results-loaded")
    }

    func testResultsEmpty() async {
        let source = PreviewDataSource()
        let model = ResultsViewModel(
            request: SearchRequest(query: "zzzz"),
            dataSource: source,
            now: now
        )
        await model.load()
        let view = ResultsView(viewModel: model)
            .environment(AppRouter())
            .environment(\.grantsDataSource, source)
        assertImage(view, named: "results-empty")
    }

    func testResultsError() async {
        let source = SnapshotFailureDataSource(base: PreviewDataSource())
        let model = ResultsViewModel(
            request: SearchRequest(),
            dataSource: source,
            now: now
        )
        await model.load()
        let view = ResultsView(viewModel: model)
            .environment(AppRouter())
            .environment(\.grantsDataSource, source)
        assertImage(view, named: "results-error")
    }

    func testFiltersSheet() {
        let values = SearchFilters(
            opportunityStatus: ["posted"],
            applicantType: [
                "nonprofits_non_higher_education_with_501c3",
                "nonprofits_non_higher_education_without_501c3"
            ],
            fundingCategory: ["health"],
            fundingInstrument: ["grant"]
        )
        let view = FiltersSheet(filters: .constant(values), query: nil)
            .environment(\.grantsDataSource, PreviewDataSource())
        assertImage(view, named: "filters-sheet")
    }

    func testDetailSimplerEnabled() async {
        let source = PreviewDataSource()
        let model = OpportunityDetailViewModel(
            opportunityId: "sample-community-health",
            dataSource: source,
            now: now
        )
        await model.load()
        let session = SessionStore(authenticator: PreviewAuthenticator())
        await session.signIn(pivRequired: false)
        let view = OpportunityDetailView(viewModel: model)
            .environment(AppRouter())
            .environment(session)
            .environment(\.grantsDataSource, source)
        assertImage(view, named: "detail-simpler-enabled")
    }

    func testDetailGrantsGov() async {
        let source = PreviewDataSource()
        let model = OpportunityDetailViewModel(
            opportunityId: "sample-rural-clinics",
            dataSource: source,
            now: now
        )
        await model.load()
        let view = OpportunityDetailView(viewModel: model)
            .environment(AppRouter())
            .environment(SessionStore(authenticator: PreviewAuthenticator()))
            .environment(\.grantsDataSource, source)
        assertImage(view, named: "detail-grants-gov")
    }

    func testDetailClosed() async {
        let source = SnapshotClosedDataSource(base: PreviewDataSource())
        let model = OpportunityDetailViewModel(
            opportunityId: "sample-community-health",
            dataSource: source,
            now: now
        )
        await model.load()
        let view = OpportunityDetailView(viewModel: model)
            .environment(AppRouter())
            .environment(SessionStore(authenticator: PreviewAuthenticator()))
            .environment(\.grantsDataSource, source)
        assertImage(view, named: "detail-closed")
    }

    func testResultsLoadedAtXXXL() async {
        let source = PreviewDataSource()
        let model = ResultsViewModel(
            request: SearchRequest(),
            dataSource: source,
            now: now
        )
        await model.load()
        let view = ResultsView(viewModel: model)
            .environment(AppRouter())
            .environment(\.grantsDataSource, source)
            .environment(\.dynamicTypeSize, .accessibility5)
        let accessibilityTraits = UITraitCollection(
            preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        let config = ViewImageConfig(
            safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            size: CGSize(width: 390, height: 844),
            traits: UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .light),
                accessibilityTraits
            ])
        )
        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: config, precision: 0.98, perceptualPrecision: 0.98),
            named: "results-loaded-xxxl",
            record: true
        )
    }

    private func assertImage<V: View>(_ view: V, named name: String) {
        let config = ViewImageConfig(
            safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            size: CGSize(width: 390, height: 844),
            traits: UITraitCollection(userInterfaceStyle: .light)
        )
        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: config, precision: 0.98, perceptualPrecision: 0.98),
            named: name,
            record: true
        )
    }
}

private actor SnapshotFailureDataSource: GrantsDataSource {
    private let base: PreviewDataSource

    init(base: PreviewDataSource) {
        self.base = base
    }

    func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        throw GrantsError.offline
    }

    func opportunity(id: String) async throws -> OpportunityDetail { try await base.opportunity(id: id) }
    func currentUser() async throws -> UserProfile { try await base.currentUser() }
    func organizations() async throws -> [Organization] { try await base.organizations() }
    func applications() async throws -> [ApplicationSummary] { try await base.applications() }
    func startApplication(competitionId: String, name: String, organizationId: String?) async throws -> String {
        try await base.startApplication(competitionId: competitionId, name: name, organizationId: organizationId)
    }
    func application(id: String) async throws -> Application { try await base.application(id: id) }
    func form(id: String) async throws -> FormDefinition { try await base.form(id: id) }
    func saveForm(applicationId: String, formId: String, response: JSONValue) async throws -> FormSaveResult {
        try await base.saveForm(applicationId: applicationId, formId: formId, response: response)
    }
    func submit(applicationId: String) async throws -> SubmissionResult { try await base.submit(applicationId: applicationId) }
    func savedOpportunityIds() async throws -> Set<String> { try await base.savedOpportunityIds() }
    func setSaved(_ saved: Bool, opportunityId: String) async throws {
        try await base.setSaved(saved, opportunityId: opportunityId)
    }
}

private actor SnapshotClosedDataSource: GrantsDataSource {
    private let base: PreviewDataSource

    init(base: PreviewDataSource) {
        self.base = base
    }

    func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        try await base.searchOpportunities(request)
    }

    func opportunity(id: String) async throws -> OpportunityDetail {
        let detail = try await base.opportunity(id: id)
        let opportunity = detail.opportunity
        let closed = Opportunity(
            opportunityId: opportunity.opportunityId,
            opportunityNumber: opportunity.opportunityNumber,
            opportunityTitle: opportunity.opportunityTitle,
            agencyCode: opportunity.agencyCode,
            agencyName: opportunity.agencyName,
            topLevelAgencyName: opportunity.topLevelAgencyName,
            category: opportunity.category,
            opportunityStatus: .closed,
            summary: opportunity.summary,
            opportunityAssistanceListings: opportunity.opportunityAssistanceListings,
            tagline: opportunity.tagline,
            agency: opportunity.agency,
            topLevelAgencyCode: opportunity.topLevelAgencyCode,
            categoryExplanation: opportunity.categoryExplanation,
            purposeStatement: opportunity.purposeStatement,
            legacyOpportunityId: opportunity.legacyOpportunityId
        )
        return OpportunityDetail(
            opportunity: closed,
            attachments: detail.attachments,
            competitions: detail.competitions
        )
    }

    func currentUser() async throws -> UserProfile { try await base.currentUser() }
    func organizations() async throws -> [Organization] { try await base.organizations() }
    func applications() async throws -> [ApplicationSummary] { try await base.applications() }
    func startApplication(competitionId: String, name: String, organizationId: String?) async throws -> String {
        try await base.startApplication(competitionId: competitionId, name: name, organizationId: organizationId)
    }
    func application(id: String) async throws -> Application { try await base.application(id: id) }
    func form(id: String) async throws -> FormDefinition { try await base.form(id: id) }
    func saveForm(applicationId: String, formId: String, response: JSONValue) async throws -> FormSaveResult {
        try await base.saveForm(applicationId: applicationId, formId: formId, response: response)
    }
    func submit(applicationId: String) async throws -> SubmissionResult { try await base.submit(applicationId: applicationId) }
    func savedOpportunityIds() async throws -> Set<String> { try await base.savedOpportunityIds() }
    func setSaved(_ saved: Bool, opportunityId: String) async throws {
        try await base.setSaved(saved, opportunityId: opportunityId)
    }
}
