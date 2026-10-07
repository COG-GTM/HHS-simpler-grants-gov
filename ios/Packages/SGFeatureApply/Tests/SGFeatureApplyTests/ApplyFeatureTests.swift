import Foundation
import SGCore
@testable import SGFeatureApply
import SGForms
import SGModels
import XCTest

final class ApplyFeatureTests: XCTestCase {
    @MainActor
    func testWorkspaceProgressAndDateCalculations() async {
        let source = ApplyReferenceDataSource(scenario: .inProgress)
        let progress = ApplyReferenceDataSource.progressStore(for: .inProgress)
        let now = fixedDate()
        let viewModel = WorkspaceViewModel(
            applicationId: nil,
            dataSource: source,
            draftStore: SpyDraftStore(),
            progressStore: progress,
            now: { now },
            timeZone: timeZone
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.completedRequiredCount, 3)
        XCTAssertEqual(viewModel.requiredCount, 6)
        XCTAssertEqual(viewModel.progressFraction, 0.5)
        XCTAssertEqual(viewModel.requiredRows.first?.state, .inProgress(completedSections: 2, totalSections: 5))
        XCTAssertEqual(viewModel.daysRemaining, 67)
        XCTAssertTrue(viewModel.isDueSoon)
        XCTAssertFalse(viewModel.canReview)
        XCTAssertEqual(viewModel.loadedApplicationId, "apply-demo")

        let complete = WorkspaceViewModel(
            applicationId: "apply-demo",
            dataSource: ApplyReferenceDataSource(scenario: .allComplete),
            draftStore: SpyDraftStore(),
            progressStore: ApplyReferenceDataSource.progressStore(for: .allComplete),
            now: { now },
            timeZone: timeZone
        )
        await complete.load()
        XCTAssertTrue(complete.canReview)
        XCTAssertEqual(complete.progressFraction, 1)

        let empty = WorkspaceViewModel(
            applicationId: nil,
            dataSource: ApplyReferenceDataSource(scenario: .empty),
            draftStore: SpyDraftStore(),
            progressStore: ApplyReferenceDataSource.progressStore(for: .empty),
            now: { now },
            timeZone: timeZone
        )
        await empty.load()
        XCTAssertEqual(empty.phase, .empty)
    }

    func testPureFormStateAndDisplayNameHelpers() {
        let sections = ["one", "two", "three"]
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "COMPLETE",
                response: .object([:]),
                hasDraft: false,
                completedSectionIds: [],
                sectionIds: sections,
                locallyComplete: false
            ),
            .complete
        )
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "in_progress",
                response: .object([:]),
                hasDraft: false,
                completedSectionIds: ["two", "unknown"],
                sectionIds: sections,
                locallyComplete: false
            ),
            .inProgress(completedSections: 1, totalSections: 3)
        )
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "not_started",
                response: .object(["email": .string("person@example.org")]),
                hasDraft: false,
                completedSectionIds: [],
                sectionIds: sections,
                locallyComplete: false
            ),
            .inProgress(completedSections: 0, totalSections: 3)
        )
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "not_started",
                response: .object([:]),
                hasDraft: true,
                completedSectionIds: [],
                sectionIds: [],
                locallyComplete: false
            ),
            .inProgress(completedSections: 0, totalSections: 1)
        )
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "not_started",
                response: .object([:]),
                hasDraft: false,
                completedSectionIds: [],
                sectionIds: [],
                locallyComplete: false
            ),
            .notStarted
        )
        XCTAssertEqual(
            ApplyFormStateLogic.displayName(
                formName: "Application for Federal Assistance (SF-424)",
                shortName: "SF-424"
            ),
            "SF-424 Application for Federal Assistance"
        )
        XCTAssertEqual(
            ApplyFormStateLogic.displayName(formName: "Project Narrative", shortName: "Narrative"),
            "Project Narrative"
        )
        XCTAssertEqual(ApplyFormStateLogic.displayName(formName: nil, shortName: nil), "")
        XCTAssertEqual(
            workspaceStateDescription(.inProgress(completedSections: 0, totalSections: 1)),
            "In progress"
        )
        XCTAssertEqual(
            workspaceStateDescription(.inProgress(completedSections: 2, totalSections: 5)),
            "In progress · 2 of 5 sections"
        )
        XCTAssertEqual(validationSummaryMessage(fieldCount: 1), "Fix 1 field before you continue.")
        XCTAssertEqual(validationSummaryMessage(fieldCount: 2), "Fix 2 fields before you continue.")
        XCTAssertEqual(workspaceFormsCompleteText(completedCount: 1, requiredCount: 1), "1 of 1 form complete")
        XCTAssertEqual(workspaceFormsCompleteText(completedCount: 3, requiredCount: 6), "3 of 6 forms complete")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dueDate = calendar.date(from: DateComponents(year: 2026, month: 12, day: 12))!
        XCTAssertEqual(
            workspaceDueLabel(date: dueDate, days: 1, timeZone: timeZone),
            "Due Dec 12 · 1 day"
        )
        XCTAssertEqual(
            workspaceDueLabel(date: dueDate, days: 67, timeZone: timeZone),
            "Due Dec 12 · 67 days"
        )
    }

    @MainActor
    func testWorkspaceResolvesOpportunityFromMatchingSummaryAndHidesMissingNumber() async throws {
        let base = ApplyReferenceDataSource(scenario: .inProgress)
        let now = fixedDate()
        let original = try await base.application(id: "apply-demo")
        let application = applicationWithoutOpportunityId(original)
        let summaries = try await base.applications()
        let fallbackSource = OpportunityResolutionTestDataSource(
            base: base,
            application: application,
            summaries: summaries
        )
        let fallback = WorkspaceViewModel(
            applicationId: "apply-demo",
            dataSource: fallbackSource,
            progressStore: ApplyReferenceDataSource.progressStore(for: .inProgress),
            now: { now },
            timeZone: timeZone
        )

        await fallback.load()

        XCTAssertEqual(fallback.opportunityNumber, "HRSA-27-014")
        let fallbackOpportunityIds = await fallbackSource.requestedOpportunityIds
        XCTAssertEqual(fallbackOpportunityIds, ["hrsa"])

        let missingSource = OpportunityResolutionTestDataSource(
            base: base,
            application: application,
            summaries: []
        )
        let missing = WorkspaceViewModel(
            applicationId: "apply-demo",
            dataSource: missingSource,
            progressStore: ApplyReferenceDataSource.progressStore(for: .inProgress),
            now: { now },
            timeZone: timeZone
        )

        await missing.load()

        XCTAssertEqual(missing.phase, .loaded)
        XCTAssertNil(missing.opportunityNumber)
        let missingOpportunityIds = await missingSource.requestedOpportunityIds
        XCTAssertEqual(missingOpportunityIds, [])
    }

    @MainActor
    func testContinueValidationGatesAndAdvances() async throws {
        let source = ApplyReferenceDataSource(scenario: .inProgress)
        let store = SpyDraftStore()
        let validationError = FieldError(
            path: "/properties/email",
            message: "Enter a valid email address, like name@organization.org"
        )
        let invalid = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: source,
            draftStore: store,
            progressStore: InMemoryFormProgressStore(),
            validator: { _, _, _ in [validationError] }
        )
        await invalid.load()
        let stayed = await invalid.continueTapped()
        XCTAssertEqual(stayed, .stayed)
        XCTAssertEqual(invalid.errors, [validationError])
        XCTAssertEqual(invalid.currentStep, 0)
        let noServerSaveCount = await source.saveCount
        XCTAssertEqual(noServerSaveCount, 0)

        let validSource = ApplyReferenceDataSource(scenario: .inProgress)
        let validStore = SpyDraftStore()
        let valid = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: validSource,
            draftStore: validStore,
            progressStore: InMemoryFormProgressStore(),
            validator: { _, _, _ in [] }
        )
        await valid.load()
        let advanced = await valid.continueTapped()
        XCTAssertEqual(advanced, .advanced)
        XCTAssertEqual(valid.currentStep, 1)
        let oneServerSave = await validSource.saveCount
        XCTAssertEqual(oneServerSave, 1)
        let locallySaved = await validStore.saveCount
        XCTAssertGreaterThanOrEqual(locallySaved, 1)

        let lastStepProgress = InMemoryFormProgressStore(
            completedSections: ["apply-demo/sf424": ["applicant", "project", "contacts", "locations"]]
        )
        let finishingSource = ApplyReferenceDataSource(scenario: .inProgress)
        let finishing = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: finishingSource,
            draftStore: SpyDraftStore(),
            progressStore: lastStepProgress,
            validator: { _, _, _ in [] }
        )
        await finishing.load()
        XCTAssertEqual(finishing.currentStep, 4)
        let finishedOutcome = await finishing.continueTapped()
        XCTAssertEqual(finishedOutcome, .finished)
        let formIsComplete = await lastStepProgress.isFormComplete(
            applicationId: "apply-demo",
            formId: "sf424"
        )
        XCTAssertTrue(formIsComplete)
    }

    @MainActor
    func testAutosaveDebouncesRapidEdits() async throws {
        let source = ApplyReferenceDataSource(scenario: .inProgress)
        let store = SpyDraftStore()
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: source,
            draftStore: store,
            progressStore: InMemoryFormProgressStore(),
            autosaveDelay: .milliseconds(50)
        )
        await viewModel.load()

        viewModel.values = .object(["email": .string("first@example.org")])
        viewModel.values = .object(["email": .string("second@example.org")])
        viewModel.values = .object(["email": .string("final@example.org")])
        try await Task.sleep(for: .milliseconds(300))

        let saveCount = await store.saveCount
        let savedValues = await store.savedValues
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(
            savedValues.last,
            .object(["email": .string("final@example.org")])
        )
    }

    @MainActor
    func testServerSaveFailureKeepsLocalDraftAndOfflineState() async {
        let serverFailure = ApplyReferenceDataSource(
            scenario: .inProgress,
            saveFailure: .server(status: 500, message: "Unavailable")
        )
        let store = SpyDraftStore()
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: serverFailure,
            draftStore: store,
            progressStore: InMemoryFormProgressStore(),
            validator: { _, _, _ in [] }
        )
        await viewModel.load()
        viewModel.values = .object(["email": .string("draft@example.org")])
        let saveFailureOutcome = await viewModel.continueTapped()
        XCTAssertEqual(saveFailureOutcome, .stayed)
        XCTAssertNotNil(viewModel.bannerMessage)
        XCTAssertEqual(viewModel.saveStatus, .failed)
        let savedValues = await store.savedValues
        XCTAssertEqual(
            savedValues.last,
            .object(["email": .string("draft@example.org")])
        )
        XCTAssertEqual(viewModel.currentStep, 0)

        let offline = ApplyReferenceDataSource(scenario: .inProgress, saveFailure: .offline)
        let offlineViewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: offline,
            draftStore: SpyDraftStore(),
            progressStore: InMemoryFormProgressStore(),
            validator: { _, _, _ in [] }
        )
        await offlineViewModel.load()
        let offlineOutcome = await offlineViewModel.continueTapped()
        XCTAssertEqual(offlineOutcome, .stayed)
        XCTAssertEqual(offlineViewModel.saveStatus, .offline)
    }

    @MainActor
    func testSubmissionGatingAuthorizationAndFailure() async {
        let inProgress = ReviewSubmitViewModel(
            applicationId: "apply-demo",
            dataSource: ApplyReferenceDataSource(scenario: .inProgress),
            draftStore: SpyDraftStore(),
            progressStore: ApplyReferenceDataSource.progressStore(for: .inProgress),
            authorizer: StubAuthorizer(result: .authorized)
        )
        await inProgress.load()
        inProgress.certified = true
        XCTAssertFalse(inProgress.canSubmit)

        let allCompleteSource = ApplyReferenceDataSource(scenario: .allComplete)
        let unavailable = ReviewSubmitViewModel(
            applicationId: "apply-demo",
            dataSource: allCompleteSource,
            draftStore: SpyDraftStore(),
            progressStore: ApplyReferenceDataSource.progressStore(for: .allComplete),
            authorizer: StubAuthorizer(result: .unavailable)
        )
        await unavailable.load()
        XCTAssertFalse(unavailable.canSubmit)
        unavailable.certified = true
        XCTAssertTrue(unavailable.canSubmit)
        let unavailableStep = await unavailable.requestSubmit()
        XCTAssertEqual(unavailableStep, .confirmationRequired)
        XCTAssertTrue(unavailable.showConfirmation)
        let noSubmission = await allCompleteSource.submitCount
        XCTAssertEqual(noSubmission, 0)

        let deniedSource = ApplyReferenceDataSource(scenario: .allComplete)
        let denied = ReviewSubmitViewModel(
            applicationId: "apply-demo",
            dataSource: deniedSource,
            draftStore: SpyDraftStore(),
            progressStore: ApplyReferenceDataSource.progressStore(for: .allComplete),
            authorizer: StubAuthorizer(result: .denied)
        )
        await denied.load()
        denied.certified = true
        let deniedStep = await denied.requestSubmit()
        XCTAssertEqual(deniedStep, .denied)
        let deniedSubmitCount = await deniedSource.submitCount
        XCTAssertEqual(deniedSubmitCount, 0)

        let authorizedSource = ApplyReferenceDataSource(scenario: .allComplete)
        let authorized = ReviewSubmitViewModel(
            applicationId: "apply-demo",
            dataSource: authorizedSource,
            draftStore: SpyDraftStore(),
            progressStore: ApplyReferenceDataSource.progressStore(for: .allComplete),
            authorizer: StubAuthorizer(result: .authorized)
        )
        await authorized.load()
        authorized.certified = true
        let authorizedStep = await authorized.requestSubmit()
        XCTAssertEqual(
            authorizedStep,
            .submitted(SubmissionResult(applicationId: "apply-demo", trackingNumber: "GRANT14102837"))
        )
        let submitCount = await authorizedSource.submitCount
        XCTAssertEqual(submitCount, 1)

        let failingSource = ApplyReferenceDataSource(
            scenario: .allComplete,
            submitFailure: .server(status: 500, message: "Unavailable")
        )
        let failing = ReviewSubmitViewModel(
            applicationId: "apply-demo",
            dataSource: failingSource,
            draftStore: SpyDraftStore(),
            progressStore: ApplyReferenceDataSource.progressStore(for: .allComplete),
            authorizer: StubAuthorizer(result: .authorized)
        )
        await failing.load()
        failing.certified = true
        let failedStep = await failing.requestSubmit()
        XCTAssertEqual(failedStep, .submitted(nil))
        XCTAssertNotNil(failing.bannerMessage)
        XCTAssertTrue(failing.certified)
    }

    private var timeZone: TimeZone {
        TimeZone(identifier: "America/New_York")!
    }

    private func fixedDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9, minute: 41))!
    }

}

private actor SpyDraftStore: DraftStore {
    private(set) var savedValues: [JSONValue] = []

    var saveCount: Int { savedValues.count }

    func loadDraft(applicationId: String, formId: String) async throws -> JSONValue? {
        nil
    }

    func saveDraft(_ value: JSONValue, applicationId: String, formId: String) async throws {
        savedValues.append(value)
    }

    func removeDraft(applicationId: String, formId: String) async throws {}
}

private struct StubAuthorizer: SubmissionAuthorizing {
    let result: SubmissionAuthorization

    func authorize(reason: String) async -> SubmissionAuthorization {
        result
    }
}

private func applicationWithoutOpportunityId(_ application: Application) -> Application {
    let original = application.competition
    let competition = Competition(
        competitionId: original.competitionId,
        competitionTitle: original.competitionTitle,
        openingDate: original.openingDate,
        closingDate: original.closingDate,
        isOpen: original.isOpen,
        isSimplerGrantsEnabled: original.isSimplerGrantsEnabled,
        openToApplicants: original.openToApplicants,
        competitionForms: original.competitionForms,
        publicCompetitionId: original.publicCompetitionId,
        contactInfo: original.contactInfo,
        gracePeriod: original.gracePeriod,
        opportunityAssistanceListing: original.opportunityAssistanceListing,
        competitionInstructions: original.competitionInstructions
    )
    return Application(
        applicationId: application.applicationId,
        applicationName: application.applicationName,
        applicationStatus: application.applicationStatus,
        competition: competition,
        organization: application.organization,
        applicationForms: application.applicationForms,
        formValidationWarnings: application.formValidationWarnings,
        intendsToAddOrganization: application.intendsToAddOrganization
    )
}

private actor OpportunityResolutionTestDataSource: GrantsDataSource {
    private let base: ApplyReferenceDataSource
    private let applicationFixture: Application
    private let summaries: [ApplicationSummary]
    private(set) var requestedOpportunityIds: [String] = []

    init(base: ApplyReferenceDataSource, application: Application, summaries: [ApplicationSummary]) {
        self.base = base
        applicationFixture = application
        self.summaries = summaries
    }

    func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        try await base.searchOpportunities(request)
    }

    func opportunity(id: String) async throws -> OpportunityDetail {
        requestedOpportunityIds.append(id)
        return try await base.opportunity(id: id)
    }

    func currentUser() async throws -> UserProfile {
        try await base.currentUser()
    }

    func organizations() async throws -> [Organization] {
        try await base.organizations()
    }

    func applications() async throws -> [ApplicationSummary] {
        summaries
    }

    func startApplication(competitionId: String, name: String, organizationId: String?) async throws -> String {
        try await base.startApplication(
            competitionId: competitionId,
            name: name,
            organizationId: organizationId
        )
    }

    func application(id: String) async throws -> Application {
        guard id == applicationFixture.applicationId else { throw GrantsError.notFound }
        return applicationFixture
    }

    func form(id: String) async throws -> FormDefinition {
        try await base.form(id: id)
    }

    func saveForm(applicationId: String, formId: String, response: JSONValue) async throws -> FormSaveResult {
        try await base.saveForm(applicationId: applicationId, formId: formId, response: response)
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
