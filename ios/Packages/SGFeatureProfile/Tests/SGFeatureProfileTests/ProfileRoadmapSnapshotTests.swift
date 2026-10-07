#if canImport(UIKit)
import SGCore
import SGDesign
import SGFeatureProfile
import SGModels
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@MainActor
final class ProfileRoadmapSnapshotTests: XCTestCase {
    private static var fontsRegistered = false
    private static let recordSnapshots = false

    override func setUp() {
        super.setUp()
        guard !Self.fontsRegistered else { return }
        SGFonts.registerAll()
        Self.fontsRegistered = true
    }

    func testProfileSignedIn() async {
        let dataSource = ProfileSnapshotDataSource()
        let model = ProfileModel()
        await model.load(from: dataSource)
        let session = SessionStore(authenticator: ProfileSnapshotAuthenticator())
        await session.signIn(pivRequired: false)

        assertView(
            profileView(model: model, session: session, dataSource: dataSource),
            named: "profile-signed-in"
        )
    }

    func testProfileGuest() async {
        let dataSource = ProfileSnapshotDataSource()
        let model = ProfileModel()
        await model.load(from: dataSource)
        let session = SessionStore(authenticator: ProfileSnapshotAuthenticator())
        session.continueAsGuest()

        assertView(
            profileView(model: model, session: session, dataSource: dataSource),
            named: "profile-guest"
        )
    }

    func testProfileExpiringSAM() async {
        let dataSource = ProfileSnapshotDataSource(expirationDate: "2026-11-06")
        let model = ProfileModel()
        await model.load(from: dataSource)
        let session = SessionStore(authenticator: ProfileSnapshotAuthenticator())
        await session.signIn(pivRequired: false)

        assertView(
            profileView(model: model, session: session, dataSource: dataSource),
            named: "profile-expiring-sam"
        )
    }

    func testRoadmap() throws {
        let content = try RoadmapContent.loadBundled()
        let suiteName = "ProfileRoadmapSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let view = RoadmapView(
            content: content,
            voteStore: RoadmapVoteStore(defaults: defaults)
        )
        assertView(view, named: "roadmap")
    }

    func testProfileSignedInAtXXXL() async {
        let dataSource = ProfileSnapshotDataSource()
        let model = ProfileModel()
        await model.load(from: dataSource)
        let session = SessionStore(authenticator: ProfileSnapshotAuthenticator())
        await session.signIn(pivRequired: false)
        let traits = UITraitCollection(
            preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
        )

        assertView(
            profileView(model: model, session: session, dataSource: dataSource),
            named: "profile-signed-in-xxxl",
            traits: traits
        )
    }

    private func profileView(
        model: ProfileModel,
        session: SessionStore,
        dataSource: ProfileSnapshotDataSource
    ) -> some View {
        ProfileView(model: model, referenceDate: Self.referenceDate)
            .environment(session)
            .environment(AppRouter(tab: .profile))
            .environment(\.grantsDataSource, dataSource)
    }

    private func assertView<Content: View>(
        _ content: Content,
        named: String,
        traits: UITraitCollection? = nil
    ) {
        let controller = UIHostingController(rootView: content)
        let snapshotting: Snapshotting<UIViewController, UIImage>
        if let traits {
            snapshotting = .image(on: .iPhone13, traits: traits)
        } else {
            snapshotting = .image(on: .iPhone13)
        }
        if Self.recordSnapshots {
            _ = verifySnapshot(of: controller, as: snapshotting, named: named, record: true)
        } else {
            assertSnapshot(of: controller, as: snapshotting, named: named, record: false)
        }
    }

    private static var referenceDate: Date {
        Calendar.samUTC.date(from: DateComponents(year: 2026, month: 10, day: 7))!
    }
}

private struct ProfileSnapshotAuthenticator: Authenticating {
    func signIn(pivRequired: Bool) async throws -> UserProfile {
        UserProfile(
            userId: "sample-dana-reyes",
            email: "dana.reyes@example.org",
            firstName: "Dana",
            lastName: "Reyes"
        )
    }

    func restore() async -> UserProfile? { nil }
    func signOut() async {}
}

private struct ProfileSnapshotDataSource: GrantsDataSource {
    private let base = PreviewDataSource()
    private let expirationDate: String?

    init(expirationDate: String? = nil) {
        self.expirationDate = expirationDate
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
        let organizations = try await base.organizations()
        guard let first = organizations.first else { return organizations }
        let entity = first.samGovEntity
        return [
            Organization(
                organizationId: first.organizationId,
                samGovEntity: SamGovEntity(
                    uei: entity?.uei,
                    legalBusinessName: entity?.legalBusinessName,
                    expirationDate: expirationDate ?? entity?.expirationDate,
                    ebizPocEmail: entity?.ebizPocEmail,
                    ebizPocFirstName: entity?.ebizPocFirstName,
                    ebizPocLastName: entity?.ebizPocLastName
                )
            )
        ]
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
        try await base.savedOpportunityIds()
    }

    func setSaved(_ saved: Bool, opportunityId: String) async throws {
        try await base.setSaved(saved, opportunityId: opportunityId)
    }
}
#endif
