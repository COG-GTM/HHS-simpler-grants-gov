import Foundation
import SGCore
@testable import SGFeatureApply
@testable import SGForms
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
        XCTAssertEqual(viewModel.requiredRows.first?.state, .inProgress(completedSteps: 2, totalSteps: 5))
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
        let steps = ["step-1", "step-2", "step-3"]
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "COMPLETE",
                response: .object([:]),
                hasDraft: false,
                hasUnsyncedDraft: false,
                completedStepIds: [],
                stepIds: steps,
                locallyComplete: false
            ),
            .complete
        )
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "in_progress",
                response: .object([:]),
                hasDraft: false,
                hasUnsyncedDraft: false,
                completedStepIds: ["step-2", "unknown"],
                stepIds: steps,
                locallyComplete: false
            ),
            .inProgress(completedSteps: 1, totalSteps: 3)
        )
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "not_started",
                response: .object(["email": .string("person@example.org")]),
                hasDraft: false,
                hasUnsyncedDraft: false,
                completedStepIds: [],
                stepIds: steps,
                locallyComplete: false
            ),
            .inProgress(completedSteps: 0, totalSteps: 3)
        )
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "not_started",
                response: .object([:]),
                hasDraft: true,
                hasUnsyncedDraft: false,
                completedStepIds: [],
                stepIds: [],
                locallyComplete: false
            ),
            .inProgress(completedSteps: 0, totalSteps: 1)
        )
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "not_started",
                response: .object([:]),
                hasDraft: false,
                hasUnsyncedDraft: false,
                completedStepIds: [],
                stepIds: [],
                locallyComplete: false
            ),
            .notStarted
        )
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "complete",
                response: .object(["email": .string("server@example.org")]),
                hasDraft: true,
                hasUnsyncedDraft: true,
                completedStepIds: [],
                stepIds: ["step-1"],
                locallyComplete: false
            ),
            .inProgress(completedSteps: 0, totalSteps: 1)
        )
        XCTAssertEqual(
            ApplyFormStateLogic.state(
                serverStatus: "complete",
                response: .object(["email": .string("same@example.org")]),
                hasDraft: true,
                hasUnsyncedDraft: false,
                completedStepIds: [],
                stepIds: ["step-1"],
                locallyComplete: false
            ),
            .complete
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
            ApplyFormStateLogic.navTitle(
                formName: "SF-424 Application for Federal Assistance",
                shortName: "SF424_4_0",
                formId: "sf424"
            ),
            "SF-424"
        )
        XCTAssertEqual(
            ApplyFormStateLogic.navTitle(
                formName: "SF-LLL Disclosure of Lobbying Activities",
                shortName: "SFLLL_2_0",
                formId: "sf-lll"
            ),
            "SF-LLL"
        )
        let parentheticalFormCodes = [
            ("Application for Federal Assistance (SF-424)", "SF-424"),
            (
                "Budget Information for Non-Construction Programs (SF-424A)",
                "SF-424A"
            ),
            (
                "Assurances for Non-Construction Programs (SF-424B)",
                "SF-424B"
            ),
            ("Disclosure of Lobbying Activities (SF-LLL)", "SF-LLL")
        ]
        for (formName, expectedTitle) in parentheticalFormCodes {
            XCTAssertEqual(
                ApplyFormStateLogic.navTitle(
                    formName: formName,
                    shortName: "raw_short_name",
                    formId: "form-id"
                ),
                expectedTitle
            )
        }
        XCTAssertEqual(
            ApplyFormStateLogic.navTitle(
                formName: "Older (SF-424) name (SF-424B)",
                shortName: "raw_short_name",
                formId: "form-id"
            ),
            "SF-424B"
        )
        XCTAssertEqual(
            ApplyFormStateLogic.navTitle(
                formName: "Project Narrative",
                shortName: "ProjectNarrative_1_0",
                formId: "project-narrative"
            ),
            "ProjectNarrative_1_0"
        )
        XCTAssertEqual(
            ApplyFormStateLogic.navTitle(
                formName: "PROJECT/PERFORMANCE SITE LOCATION(S)",
                shortName: "Site_1_0",
                formId: "site"
            ),
            "Site_1_0"
        )
        XCTAssertEqual(
            ApplyFormStateLogic.navTitle(
                formName: "Project Narrative Attachment Form",
                shortName: "ProjectNarrative_1_0",
                formId: "narrative"
            ),
            "ProjectNarrative_1_0"
        )
        XCTAssertEqual(
            ApplyFormStateLogic.navTitle(
                formName: nil,
                shortName: "SF424_4_0",
                formId: "sf424"
            ),
            "SF424_4_0"
        )
        XCTAssertEqual(
            workspaceStateDescription(.inProgress(completedSteps: 0, totalSteps: 1)),
            "In progress"
        )
        XCTAssertEqual(
            workspaceStateDescription(.inProgress(completedSteps: 2, totalSteps: 5)),
            "In progress · 2 of 5 steps"
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

    func testCompletedStepIdsMigratesFullyCompletedLegacySections() throws {
        let steps = try FormModel(definition: multiSectionStepDefinition()).steps
        let firstStep = try XCTUnwrap(steps.first)
        let secondStep = steps[1]
        let thirdStep = steps[2]
        let stored = Set([
            firstStep.id,
            secondStep.sections[0].id,
            secondStep.sections[1].id,
            thirdStep.id,
            "unknown"
        ])

        XCTAssertEqual(
            completedStepIds(stored: stored, steps: steps),
            Set([firstStep.id, secondStep.id, thirdStep.id])
        )
        XCTAssertTrue(completedStepIds(stored: ["applicant_information"], steps: steps).isEmpty)
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
    func testWorkspaceDeadlineUsesConfiguredCalendarAcrossDSTBoundary() async throws {
        let base = ApplyReferenceDataSource(scenario: .inProgress)
        let original = try await base.application(id: "apply-demo")
        let application = applicationWithoutOpportunityId(original, closingDate: "2026-03-08")
        let source = OpportunityResolutionTestDataSource(
            base: base,
            application: application,
            summaries: try await base.applications()
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 7, hour: 12)
        )!
        let viewModel = WorkspaceViewModel(
            applicationId: "apply-demo",
            dataSource: source,
            progressStore: ApplyReferenceDataSource.progressStore(for: .inProgress),
            now: { now },
            timeZone: timeZone
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.daysRemaining, 1)
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
            completedSections: ["apply-demo/sf424": ["step-1", "step-2", "step-3", "step-4"]]
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
    func testContinueValidatesEverySectionInCurrentStep() async {
        let firstError = FieldError(path: "$.first", message: "First section error")
        let secondError = FieldError(path: "$.second", message: "Second section error")
        let errorsBySection = [
            "applicant_information": [firstError],
            "applicant_contact": [secondError]
        ]
        let progress = InMemoryFormProgressStore(
            completedSections: ["apply-demo/sf424": ["step-1"]]
        )
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: multiSectionStepDefinition()
            ),
            progressStore: progress,
            validator: { _, section, _ in errorsBySection[section.id] ?? [] }
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.currentStep, 1)
        XCTAssertEqual(viewModel.currentFormStep?.sections.map(\.id), [
            "applicant_information",
            "applicant_contact"
        ])

        let outcome = await viewModel.continueTapped()

        XCTAssertEqual(outcome, .stayed)
        XCTAssertEqual(viewModel.sectionErrors["applicant_information"], [firstError])
        XCTAssertEqual(viewModel.sectionErrors["applicant_contact"], [secondError])
        XCTAssertEqual(viewModel.revealedSectionErrors["applicant_information"], [firstError])
        XCTAssertEqual(viewModel.revealedSectionErrors["applicant_contact"], [secondError])
        XCTAssertEqual(viewModel.errors, [firstError, secondError])
        XCTAssertEqual(viewModel.firstErrorSectionID, "applicant_information")
    }

    @MainActor
    func testLastStepShowsOnlyTheFirstInvalidStepErrors() async {
        let firstError = FieldError(path: "$.submission_type", message: "Step one error")
        let thirdError = FieldError(path: "$.federal_agency", message: "Step three error")
        let progress = InMemoryFormProgressStore(
            completedSections: ["apply-demo/sf424": ["step-1", "step-2", "step-3", "step-4"]]
        )
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: multiSectionStepDefinition()
            ),
            progressStore: progress,
            validator: { _, section, _ in
                switch section.id {
                case "submission_type": [firstError]
                case "federal_agency": [thirdError]
                default: []
                }
            }
        )
        await viewModel.load()
        XCTAssertEqual(viewModel.currentStep, 4)

        let outcome = await viewModel.continueTapped()

        XCTAssertEqual(outcome, .stayed)
        XCTAssertEqual(viewModel.currentStep, 0)
        XCTAssertEqual(viewModel.errors, [firstError])
        XCTAssertEqual(viewModel.sectionErrors["submission_type"], [firstError])
        XCTAssertFalse(viewModel.errors.contains(thirdError))
        XCTAssertFalse(viewModel.sectionErrors.values.flatMap { $0 }.contains(thirdError))
    }

    @MainActor
    func testResumeStartsAtFirstIncompleteStep() async throws {
        let progress = InMemoryFormProgressStore(
            completedSections: ["apply-demo/sf424": ["step-1", "step-2", "step-4"]]
        )
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: try FormPreviewSamples.sf424Definition()
            ),
            progressStore: progress
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.steps.count, 5)
        XCTAssertEqual(viewModel.currentStep, 2)
        XCTAssertEqual(viewModel.currentFormStep?.id, "step-3")
    }

    @MainActor
    func testRealSF424EmailValidationAndCorrection() async throws {
        let progress = InMemoryFormProgressStore(
            completedSections: ["apply-demo/sf424": ["step-1"]]
        )
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: try FormPreviewSamples.sf424Definition()
            ),
            progressStore: progress
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.shortName, "SF-424")
        let model = try XCTUnwrap(viewModel.model)
        let step = try XCTUnwrap(viewModel.currentFormStep)
        XCTAssertEqual(viewModel.currentStep, 1)
        XCTAssertEqual(step.title, "Applicant information")
        XCTAssertTrue(step.sections.flatMap(\.fields).contains { $0.path == "/properties/email" })
        let fields = step.sections.flatMap(\.fields)
        let legalNameField = try XCTUnwrap(
            fields.first { $0.path == "/properties/organization_name" }
        )
        let ueiField = try XCTUnwrap(fields.first { $0.path == "/properties/sam_uei" })
        XCTAssertTrue(ueiField.isReadOnly)
        for field in [legalNameField, ueiField] {
            let prefilledValue = try XCTUnwrap(viewModel.prefill[field.path])
            XCTAssertEqual(viewModel.prefill[field.dataPath.jsonPath], prefilledValue)
            XCTAssertEqual(viewModel.prefill[field.dataPath.lastKey ?? ""], prefilledValue)
            XCTAssertEqual(
                viewModel.values.value(at: field.dataPath),
                .string(prefilledValue)
            )
        }

        viewModel.values = validValues(
            for: step,
            model: model,
            startingWith: viewModel.values
        )
        viewModel.values.setValue(.string("dana@bluefieldchc"), at: FieldPath(keys: ["email"]))
        let invalidOutcome = await viewModel.continueTapped()

        XCTAssertEqual(invalidOutcome, .stayed)
        XCTAssertTrue(viewModel.errors.contains {
            $0.path == "$.email"
                && $0.message == "Enter a valid email address, like name@organization.org"
        })
        XCTAssertEqual(viewModel.currentStep, 1)

        viewModel.values.setValue(.string("dana@bluefieldchc.org"), at: FieldPath(keys: ["email"]))
        let validOutcome = await viewModel.continueTapped()

        XCTAssertEqual(validOutcome, .advanced)
        XCTAssertEqual(viewModel.currentStep, 2)
    }

    @MainActor
    func testAttachSingleRequiredAttachmentAndValidate() async throws {
        let definition = attachmentFormDefinition(array: false)
        let attachmentStore = InMemoryApplyAttachmentStore()
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: definition
            ),
            draftStore: SpyDraftStore(),
            progressStore: InMemoryFormProgressStore(),
            attachmentStore: attachmentStore,
            autosaveDelay: .seconds(30)
        )
        await viewModel.load()
        let model = try XCTUnwrap(viewModel.model)
        let section = try XCTUnwrap(model.sections.first)
        let field = try XCTUnwrap(section.fields.first)
        XCTAssertEqual(field.kind, .attachment)
        XCTAssertEqual(FormValidator.validate(viewModel.values, section: section, model: model).count, 1)

        await viewModel.attachFiles(FormAttachmentRequest(
            field: field,
            path: field.dataPath,
            urls: [URL(fileURLWithPath: "/fictional/required-support.pdf")]
        ))

        guard case let .string(id)? = viewModel.values.value(at: field.dataPath) else {
            return XCTFail("Expected an attachment id at the field path")
        }
        XCTAssertTrue(id.hasPrefix("demo-attachment-"))
        XCTAssertEqual(viewModel.attachmentNames[id], "required-support.pdf")
        XCTAssertTrue(FormValidator.validate(viewModel.values, section: section, model: model).isEmpty)
    }

    @MainActor
    func testAttachMultipleFilesAppendsToAttachmentArray() async throws {
        let definition = attachmentFormDefinition(array: true)
        let attachmentStore = InMemoryApplyAttachmentStore()
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: definition
            ),
            draftStore: SpyDraftStore(),
            progressStore: InMemoryFormProgressStore(),
            attachmentStore: attachmentStore,
            autosaveDelay: .seconds(30)
        )
        await viewModel.load()
        let model = try XCTUnwrap(viewModel.model)
        let section = try XCTUnwrap(model.sections.first)
        let field = try XCTUnwrap(section.fields.first)
        XCTAssertEqual(field.kind, .attachmentArray)
        viewModel.values.setValue(.array([.string("existing-attachment")]), at: field.dataPath)

        await viewModel.attachFiles(FormAttachmentRequest(
            field: field,
            path: field.dataPath,
            urls: [
                URL(fileURLWithPath: "/fictional/first-support.pdf"),
                URL(fileURLWithPath: "/fictional/second-support.pdf")
            ]
        ))

        guard case let .array(ids)? = viewModel.values.value(at: field.dataPath) else {
            return XCTFail("Expected attachment ids at the array field path")
        }
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(ids.first, .string("existing-attachment"))
        let newIds = ids.dropFirst().compactMap {
            if case let .string(id) = $0 { return id }
            return nil
        }
        XCTAssertEqual(newIds.count, 2)
        XCTAssertEqual(viewModel.attachmentNames[newIds[0]], "first-support.pdf")
        XCTAssertEqual(viewModel.attachmentNames[newIds[1]], "second-support.pdf")
        XCTAssertTrue(FormValidator.validate(viewModel.values, section: section, model: model).isEmpty)
    }

    @MainActor
    func testFailedAttachmentStoreLeavesValuesUnchangedAndShowsBanner() async throws {
        let definition = attachmentFormDefinition(array: false)
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: definition
            ),
            draftStore: SpyDraftStore(),
            progressStore: InMemoryFormProgressStore(),
            attachmentStore: InMemoryApplyAttachmentStore(shouldFail: true),
            autosaveDelay: .seconds(30)
        )
        await viewModel.load()
        let model = try XCTUnwrap(viewModel.model)
        let field = try XCTUnwrap(model.sections.first?.fields.first)
        let originalValues = viewModel.values

        await viewModel.attachFiles(FormAttachmentRequest(
            field: field,
            path: field.dataPath,
            urls: [URL(fileURLWithPath: "/fictional/failed-support.pdf")]
        ))

        XCTAssertEqual(viewModel.values, originalValues)
        XCTAssertTrue(viewModel.attachmentNames.isEmpty)
        XCTAssertEqual(
            viewModel.bannerMessage,
            "We couldn't attach that file. Try again."
        )
    }

    @MainActor
    func testSaveDraftWaitsForPendingAttachmentStorage() async throws {
        let definition = attachmentFormDefinition(array: false)
        let source = SuspendingSaveDataSource(
            base: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: definition
            )
        )
        let draftStore = SpyDraftStore()
        let attachmentStore = SuspendingApplyAttachmentStore()
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: source,
            draftStore: draftStore,
            progressStore: InMemoryFormProgressStore(),
            attachmentStore: attachmentStore,
            autosaveDelay: .seconds(30)
        )
        await viewModel.load()
        let field = try XCTUnwrap(viewModel.model?.sections.first?.fields.first)
        let request = FormAttachmentRequest(
            field: field,
            path: field.dataPath,
            urls: [URL(fileURLWithPath: "/fictional/slow-support.pdf")]
        )

        viewModel.attach(request)
        await attachmentStore.waitUntilStoreStarts()
        XCTAssertTrue(viewModel.isAttaching)
        let saveTask = Task { @MainActor in await viewModel.saveDraftTapped() }

        await attachmentStore.releaseStore()
        await source.waitForFirstSave()

        let attachmentId = "demo-attachment-slow"
        let savedValues = await draftStore.savedValues
        let serverResponses = await source.receivedResponses
        XCTAssertEqual(
            savedValues.last?.value(at: field.dataPath),
            .string(attachmentId)
        )
        XCTAssertEqual(
            serverResponses.first?.value(at: field.dataPath),
            .string(attachmentId)
        )

        await source.releaseFirstSave()
        let didSave = await saveTask.value
        XCTAssertTrue(didSave)
        XCTAssertFalse(viewModel.isAttaching)
    }

    @MainActor
    func testRetryRetriesFailedAttachmentAndClearsBanner() async throws {
        let definition = attachmentFormDefinition(array: false)
        let attachmentStore = InMemoryApplyAttachmentStore(failuresRemaining: 1)
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: definition
            ),
            draftStore: SpyDraftStore(),
            progressStore: InMemoryFormProgressStore(),
            attachmentStore: attachmentStore,
            autosaveDelay: .seconds(30)
        )
        await viewModel.load()
        let field = try XCTUnwrap(viewModel.model?.sections.first?.fields.first)
        let request = FormAttachmentRequest(
            field: field,
            path: field.dataPath,
            urls: [URL(fileURLWithPath: "/fictional/retry-support.pdf")]
        )

        await viewModel.attachFiles(request)
        XCTAssertNotNil(viewModel.bannerMessage)

        await viewModel.retry()

        guard case let .string(id)? = viewModel.values.value(at: field.dataPath) else {
            return XCTFail("Expected the retried attachment id at the field path")
        }
        XCTAssertTrue(id.hasPrefix("demo-attachment-"))
        XCTAssertEqual(viewModel.attachmentNames[id], "retry-support.pdf")
        XCTAssertNil(viewModel.bannerMessage)
    }

    @MainActor
    func testAttachmentBatchRollsBackEarlierFilesWhenLaterCopyFails() async throws {
        let definition = attachmentFormDefinition(array: true)
        let attachmentStore = InMemoryApplyAttachmentStore(failingStoreCalls: [2])
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: definition
            ),
            draftStore: SpyDraftStore(),
            progressStore: InMemoryFormProgressStore(),
            attachmentStore: attachmentStore,
            autosaveDelay: .seconds(30)
        )
        await viewModel.load()
        let field = try XCTUnwrap(viewModel.model?.sections.first?.fields.first)
        let originalValues = viewModel.values

        await viewModel.attachFiles(FormAttachmentRequest(
            field: field,
            path: field.dataPath,
            urls: [
                URL(fileURLWithPath: "/fictional/first-batch.pdf"),
                URL(fileURLWithPath: "/fictional/second-batch.pdf")
            ]
        ))

        XCTAssertEqual(viewModel.values, originalValues)
        let storedNames = await attachmentStore.names(
            applicationId: "apply-demo",
            formId: "sf424"
        )
        XCTAssertTrue(storedNames.isEmpty)
        XCTAssertTrue(viewModel.attachmentNames.isEmpty)
    }

    @MainActor
    func testSavingReplacementPrunesOldAttachmentAndKeepsNewOne() async throws {
        let definition = attachmentFormDefinition(array: false)
        let attachmentStore = InMemoryApplyAttachmentStore()
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: definition
            ),
            draftStore: SpyDraftStore(),
            progressStore: InMemoryFormProgressStore(),
            attachmentStore: attachmentStore,
            autosaveDelay: .seconds(30)
        )
        await viewModel.load()
        let field = try XCTUnwrap(viewModel.model?.sections.first?.fields.first)

        await viewModel.attachFiles(FormAttachmentRequest(
            field: field,
            path: field.dataPath,
            urls: [URL(fileURLWithPath: "/fictional/old-support.pdf")]
        ))
        guard case let .string(oldID)? = viewModel.values.value(at: field.dataPath) else {
            return XCTFail("Expected the first attachment id at the field path")
        }

        await viewModel.attachFiles(FormAttachmentRequest(
            field: field,
            path: field.dataPath,
            urls: [URL(fileURLWithPath: "/fictional/new-support.pdf")]
        ))
        guard case let .string(newID)? = viewModel.values.value(at: field.dataPath) else {
            return XCTFail("Expected the replacement attachment id at the field path")
        }
        XCTAssertNotEqual(oldID, newID)

        let didFlush = await viewModel.flushDraft()
        XCTAssertTrue(didFlush)

        let storedNames = await attachmentStore.names(
            applicationId: "apply-demo",
            formId: "sf424"
        )
        XCTAssertNil(storedNames[oldID])
        XCTAssertEqual(storedNames[newID], "new-support.pdf")
        XCTAssertNil(viewModel.attachmentNames[oldID])
        XCTAssertEqual(viewModel.attachmentNames[newID], "new-support.pdf")
    }

    @MainActor
    func testAttachmentPruningPreservesDraftSnapshotDuringSuspendedSave() async throws {
        let definition = attachmentFormDefinition(array: false)
        let attachmentStore = InMemoryApplyAttachmentStore()
        let draftStore = SuspendingDraftStore()
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: definition
            ),
            draftStore: draftStore,
            progressStore: InMemoryFormProgressStore(),
            attachmentStore: attachmentStore,
            autosaveDelay: .seconds(30)
        )
        await viewModel.load()
        let field = try XCTUnwrap(viewModel.model?.sections.first?.fields.first)

        await viewModel.attachFiles(FormAttachmentRequest(
            field: field,
            path: field.dataPath,
            urls: [URL(fileURLWithPath: "/fictional/saved-support.pdf")]
        ))
        guard case let .string(savedID)? = viewModel.values.value(at: field.dataPath) else {
            return XCTFail("Expected the saved attachment id at the field path")
        }

        let saveTask = Task { @MainActor in await viewModel.flushDraft() }
        await draftStore.waitUntilFirstSaveStarts()

        await viewModel.attachFiles(FormAttachmentRequest(
            field: field,
            path: field.dataPath,
            urls: [URL(fileURLWithPath: "/fictional/live-support.pdf")]
        ))
        guard case let .string(liveID)? = viewModel.values.value(at: field.dataPath) else {
            return XCTFail("Expected the live attachment id at the field path")
        }
        XCTAssertNotEqual(savedID, liveID)

        await draftStore.releaseFirstSave()
        let didFlush = await saveTask.value
        XCTAssertTrue(didFlush)

        let firstSave = await draftStore.savedValues.first
        XCTAssertEqual(firstSave?.value(at: field.dataPath), .string(savedID))
        var storedNames = await attachmentStore.names(
            applicationId: "apply-demo",
            formId: "sf424"
        )
        XCTAssertEqual(storedNames[savedID], "saved-support.pdf")
        XCTAssertEqual(storedNames[liveID], "live-support.pdf")

        let didFlushAgain = await viewModel.flushDraft()
        XCTAssertTrue(didFlushAgain)

        let savedValues = await draftStore.savedValues
        XCTAssertEqual(savedValues.last?.value(at: field.dataPath), .string(liveID))
        storedNames = await attachmentStore.names(
            applicationId: "apply-demo",
            formId: "sf424"
        )
        XCTAssertNil(storedNames[savedID])
        XCTAssertEqual(storedNames[liveID], "live-support.pdf")
    }

    @MainActor
    func testLoadRestoresAttachmentNamesFromStore() async throws {
        let attachmentStore = InMemoryApplyAttachmentStore()
        let stored = try await attachmentStore.store(
            URL(fileURLWithPath: "/fictional/restored-support.pdf"),
            applicationId: "apply-demo",
            formId: "sf424"
        )
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(scenario: .inProgress),
            draftStore: SpyDraftStore(),
            progressStore: InMemoryFormProgressStore(),
            attachmentStore: attachmentStore,
            autosaveDelay: .seconds(30)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.attachmentNames[stored.id], stored.name)
    }

    func testFileAttachmentStoreCopiesFileAndPersistsNames() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("apply-attachment-\(UUID().uuidString)", isDirectory: true)
        let applicationSupportURL = temporaryDirectory.appendingPathComponent(
            "application-support",
            isDirectory: true
        )
        let sourceDirectory = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceURL = sourceDirectory.appendingPathComponent("support.pdf")
        let sourceContents = Data("sample attachment".utf8)
        try sourceContents.write(to: sourceURL)
        let store = FileApplyAttachmentStore(applicationSupportURL: applicationSupportURL)

        let stored = try await store.store(
            sourceURL,
            applicationId: "apply-demo",
            formId: "sf424"
        )

        let formDirectory = applicationSupportURL
            .appendingPathComponent("SGApply", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent("apply-demo", isDirectory: true)
            .appendingPathComponent("sf424", isDirectory: true)
        let copiedURL = formDirectory
            .appendingPathComponent(stored.id, isDirectory: true)
            .appendingPathComponent("support.pdf")
        XCTAssertEqual(try Data(contentsOf: copiedURL), sourceContents)
        XCTAssertTrue(stored.id.hasPrefix("demo-attachment-"))
        let attachmentNames = await store.names(applicationId: "apply-demo", formId: "sf424")
        XCTAssertEqual(attachmentNames[stored.id], "support.pdf")
        let namesData = try Data(contentsOf: formDirectory.appendingPathComponent("names.json"))
        let persistedNames = try JSONDecoder().decode([String: String].self, from: namesData)
        XCTAssertEqual(persistedNames[stored.id], "support.pdf")

        let retained = try await store.store(
            sourceURL,
            applicationId: "apply-demo",
            formId: "sf424"
        )
        let retainedURL = formDirectory
            .appendingPathComponent(retained.id, isDirectory: true)
            .appendingPathComponent("support.pdf")
        await store.prune(
            keeping: [retained.id],
            applicationId: "apply-demo",
            formId: "sf424"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedURL.path))
        let namesAfterPrune = await store.names(
            applicationId: "apply-demo",
            formId: "sf424"
        )
        XCTAssertEqual(namesAfterPrune, [retained.id: "support.pdf"])

        await store.remove(
            ids: [retained.id],
            applicationId: "apply-demo",
            formId: "sf424"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: retainedURL.path))
        let namesAfterRemoval = await store.names(
            applicationId: "apply-demo",
            formId: "sf424"
        )
        XCTAssertTrue(namesAfterRemoval.isEmpty)
    }

    @MainActor
    func testMatchingResponseValuesRemainVerifiedPrefill() async throws {
        let definition = try FormPreviewSamples.sf424Definition()
        let base = ApplyReferenceDataSource(
            scenario: .inProgress,
            sf424Definition: definition
        )
        let originalApplication = try await base.application(id: "apply-demo")
        let originalForm = try XCTUnwrap(
            originalApplication.applicationForms.first { $0.formId == "sf424" }
        )
        var response = originalForm.applicationResponse
        response.setValue(
            .string("Bluefield Community Health Center"),
            at: FieldPath(keys: ["organization_name"])
        )
        response.setValue(
            .string("K7LMN2QX4R91"),
            at: FieldPath(keys: ["sam_uei"])
        )
        let forms = originalApplication.applicationForms.map { form in
            guard form.formId == "sf424" else { return form }
            return ApplicationForm(
                applicationFormId: form.applicationFormId,
                formId: form.formId,
                form: form.form,
                applicationResponse: response,
                applicationFormStatus: form.applicationFormStatus,
                isRequired: form.isRequired,
                isIncludedInSubmission: form.isIncludedInSubmission,
                applicationId: form.applicationId,
                applicationName: form.applicationName
            )
        }
        let application = Application(
            applicationId: originalApplication.applicationId,
            applicationName: originalApplication.applicationName,
            applicationStatus: originalApplication.applicationStatus,
            competition: originalApplication.competition,
            organization: originalApplication.organization,
            applicationForms: forms,
            formValidationWarnings: originalApplication.formValidationWarnings,
            intendsToAddOrganization: originalApplication.intendsToAddOrganization
        )
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: OpportunityResolutionTestDataSource(
                base: base,
                application: application,
                summaries: []
            ),
            progressStore: InMemoryFormProgressStore()
        )

        await viewModel.load()

        let fields = viewModel.steps.flatMap(\.sections).flatMap(\.fields)
        for (path, expectedValue) in [
            ("/properties/organization_name", "Bluefield Community Health Center"),
            ("/properties/sam_uei", "K7LMN2QX4R91")
        ] {
            let field = try XCTUnwrap(fields.first { $0.path == path })
            XCTAssertEqual(viewModel.prefill[field.path], expectedValue)
            XCTAssertTrue(viewModel.prefilledPaths.contains(field.path))
            XCTAssertEqual(
                viewModel.values.value(at: field.dataPath),
                .string(expectedValue)
            )
        }
    }

    @MainActor
    func testEditingCompletedFormClearsLocalCompletion() async {
        let stepIds: Set<String> = ["step-1", "step-2", "step-3", "step-4", "step-5"]
        let progress = InMemoryFormProgressStore(
            completedSections: ["apply-demo/sf424": stepIds],
            completeForms: ["apply-demo/sf424"]
        )
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(scenario: .allComplete),
            draftStore: SpyDraftStore(),
            progressStore: progress
        )

        await viewModel.load()
        viewModel.values = .object(["email": .string("edited@example.org")])
        _ = await viewModel.flushDraft()

        let isComplete = await progress.isFormComplete(applicationId: "apply-demo", formId: "sf424")
        let completedSections = await progress.completedSections(applicationId: "apply-demo", formId: "sf424")
        XCTAssertFalse(isComplete)
        XCTAssertFalse(completedSections.contains("step-1"))
    }

    @MainActor
    func testEditingNextCompletedStepClearsOnlyThatStepProgress() async throws {
        let base = ApplyReferenceDataSource(scenario: .inProgress)
        let originalApplication = try await base.application(id: "apply-demo")
        let originalForm = try XCTUnwrap(
            originalApplication.applicationForms.first { $0.formId == "sf424" }
        )
        let twoSectionForm = FormDefinition(
            formId: originalForm.formId,
            formName: originalForm.form.formName,
            shortFormName: originalForm.form.shortFormName,
            formJsonSchema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ]),
            formUiSchema: .array([
                .object([
                    "type": .string("section"),
                    "name": .string("section-one"),
                    "label": .string("Section one"),
                    "children": .array([])
                ]),
                .object([
                    "type": .string("section"),
                    "name": .string("section-two"),
                    "label": .string("Section two"),
                    "children": .array([])
                ])
            ])
        )
        let forms = originalApplication.applicationForms.map { form in
            guard form.formId == originalForm.formId else { return form }
            return ApplicationForm(
                applicationFormId: form.applicationFormId,
                formId: form.formId,
                form: twoSectionForm,
                applicationResponse: form.applicationResponse,
                applicationFormStatus: form.applicationFormStatus,
                isRequired: form.isRequired,
                isIncludedInSubmission: form.isIncludedInSubmission,
                applicationId: form.applicationId,
                applicationName: form.applicationName
            )
        }
        let application = Application(
            applicationId: originalApplication.applicationId,
            applicationName: originalApplication.applicationName,
            applicationStatus: originalApplication.applicationStatus,
            competition: originalApplication.competition,
            organization: originalApplication.organization,
            applicationForms: forms,
            formValidationWarnings: originalApplication.formValidationWarnings,
            intendsToAddOrganization: originalApplication.intendsToAddOrganization
        )
        let dataSource = OpportunityResolutionTestDataSource(
            base: base,
            application: application,
            summaries: []
        )
        let progress = InMemoryFormProgressStore(
            completedSections: ["apply-demo/sf424": ["step-1", "step-2"]],
            completeForms: ["apply-demo/sf424"]
        )
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: dataSource,
            draftStore: SpyDraftStore(),
            progressStore: progress,
            validator: { _, _, _ in [] }
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.currentStep, 0)
        XCTAssertEqual(viewModel.currentFormStep?.sections.first?.id, "section-one")

        viewModel.values = .object(["first": .string("edited")])
        let firstOutcome = await viewModel.continueTapped()
        XCTAssertEqual(firstOutcome, .advanced)
        XCTAssertEqual(viewModel.currentStep, 1)

        viewModel.values = .object(["second": .string("edited")])
        _ = await viewModel.flushDraft()

        let completedSections = await progress.completedSections(
            applicationId: "apply-demo",
            formId: "sf424"
        )
        XCTAssertTrue(completedSections.contains("step-1"))
        XCTAssertFalse(completedSections.contains("step-2"))
    }

    @MainActor
    func testSuccessfulServerSaveMarksDraftSynced() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let draftStore = FileDraftStore(directoryURL: directory)
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(scenario: .inProgress),
            draftStore: draftStore,
            progressStore: InMemoryFormProgressStore()
        )

        await viewModel.load()
        viewModel.values = .object(["email": .string("saved@example.org")])

        let didSync = await viewModel.syncToServer()
        let pendingDrafts = try await draftStore.pendingDrafts()
        XCTAssertTrue(didSync)
        XCTAssertTrue(pendingDrafts.isEmpty)
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
    func testOverlappingServerSavesAreSerializedAndUseCurrentValues() async throws {
        let source = SuspendingSaveDataSource(base: ApplyReferenceDataSource(scenario: .inProgress))
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: source,
            draftStore: SpyDraftStore(),
            progressStore: InMemoryFormProgressStore(),
            validator: { _, _, _ in [] }
        )
        await viewModel.load()

        let valueA = JSONValue.object(["email": .string("a@example.org")])
        let valueB = JSONValue.object(["email": .string("b@example.org")])
        viewModel.values = valueA
        let firstSave = Task { @MainActor in await viewModel.syncToServer() }
        await source.waitForFirstSave()

        viewModel.values = valueB
        let secondSave = Task { @MainActor in await viewModel.syncToServer() }
        try await Task.sleep(for: .milliseconds(50))
        let responsesBeforeFirstSaveCompletes = await source.receivedResponses
        XCTAssertEqual(responsesBeforeFirstSaveCompletes, [valueA])

        await source.releaseFirstSave()
        let firstSaveResult = await firstSave.value
        let secondSaveResult = await secondSave.value
        XCTAssertTrue(firstSaveResult)
        XCTAssertTrue(secondSaveResult)
        let receivedResponses = await source.receivedResponses
        XCTAssertEqual(receivedResponses, [valueA, valueB])
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
    func testReviewWarningsPreferLatestCachedValuesWithoutDuplicates() async throws {
        let base = ApplyReferenceDataSource(scenario: .allComplete)
        let original = try await base.application(id: "apply-demo")
        let sf424 = try XCTUnwrap(original.applicationForms.first { $0.formId == "sf424" })
        let applicationId = "review-warning-dedupe"
        let expectedWarnings = [
            ValidationWarning(field: "email", message: "Email format warning", type: "format"),
            ValidationWarning(
                field: "organization_name",
                message: "Organization name warning",
                type: "required"
            )
        ]
        let application = applicationWithFormWarnings(
            original,
            applicationId: applicationId,
            formValidationWarnings: .object([
                sf424.applicationFormId: persistedWarningValues(expectedWarnings)
            ])
        )
        await ApplyWarningsCache.shared.set(
            expectedWarnings,
            applicationId: applicationId,
            formId: sf424.formId
        )
        let viewModel = ReviewSubmitViewModel(
            applicationId: applicationId,
            dataSource: OpportunityResolutionTestDataSource(
                base: base,
                application: application,
                summaries: []
            ),
            draftStore: SpyDraftStore(),
            progressStore: ApplyReferenceDataSource.progressStore(for: .allComplete),
            authorizer: StubAuthorizer(result: .authorized)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.warnings.count, 2)
        XCTAssertEqual(viewModel.warnings.map(\.message), expectedWarnings.map(\.message))
        XCTAssertEqual(viewModel.warnings.map(\.id), [
            "sf424/email/Email format warning",
            "sf424/organization_name/Organization name warning"
        ])
    }

    @MainActor
    func testReviewWarningsEmptyCacheOverridesPersistedWarnings() async throws {
        let base = ApplyReferenceDataSource(scenario: .allComplete)
        let original = try await base.application(id: "apply-demo")
        let sf424 = try XCTUnwrap(original.applicationForms.first { $0.formId == "sf424" })
        let applicationId = "review-warning-empty-cache"
        let persistedWarnings = [
            ValidationWarning(field: "email", message: "Email format warning", type: "format"),
            ValidationWarning(
                field: "organization_name",
                message: "Organization name warning",
                type: "required"
            )
        ]
        let application = applicationWithFormWarnings(
            original,
            applicationId: applicationId,
            formValidationWarnings: .object([
                sf424.applicationFormId: persistedWarningValues(persistedWarnings)
            ])
        )
        await ApplyWarningsCache.shared.set(
            [],
            applicationId: applicationId,
            formId: sf424.formId
        )
        let cachedWarnings = await ApplyWarningsCache.shared.all(applicationId: applicationId)
        XCTAssertTrue(cachedWarnings.keys.contains(sf424.formId))
        XCTAssertTrue(cachedWarnings[sf424.formId]?.isEmpty == true)
        let viewModel = ReviewSubmitViewModel(
            applicationId: applicationId,
            dataSource: OpportunityResolutionTestDataSource(
                base: base,
                application: application,
                summaries: []
            ),
            draftStore: SpyDraftStore(),
            progressStore: ApplyReferenceDataSource.progressStore(for: .allComplete),
            authorizer: StubAuthorizer(result: .authorized)
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.warnings.isEmpty)
    }

    @MainActor
    func testReviewWarningsDedupePersistedValuesByFormFieldAndMessage() async throws {
        let base = ApplyReferenceDataSource(scenario: .allComplete)
        let original = try await base.application(id: "apply-demo")
        let sf424 = try XCTUnwrap(original.applicationForms.first { $0.formId == "sf424" })
        let applicationId = "review-warning-persisted-dedup"
        let expectedWarnings = [
            ValidationWarning(field: "email", message: "Email format warning", type: "format"),
            ValidationWarning(
                field: "organization_name",
                message: "Organization name warning",
                type: "required"
            )
        ]
        let persistedValues = persistedWarningValues(expectedWarnings)
        let application = applicationWithFormWarnings(
            original,
            applicationId: applicationId,
            formValidationWarnings: .object([
                sf424.applicationFormId: persistedValues,
                sf424.formId: persistedValues
            ])
        )
        let viewModel = ReviewSubmitViewModel(
            applicationId: applicationId,
            dataSource: OpportunityResolutionTestDataSource(
                base: base,
                application: application,
                summaries: []
            ),
            draftStore: SpyDraftStore(),
            progressStore: ApplyReferenceDataSource.progressStore(for: .allComplete),
            authorizer: StubAuthorizer(result: .authorized)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.warnings.count, 2)
        XCTAssertEqual(viewModel.warnings.map(\.message), expectedWarnings.map(\.message))
        XCTAssertEqual(viewModel.warnings.map(\.id), [
            "sf424/email/Email format warning",
            "sf424/organization_name/Organization name warning"
        ])
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

    @MainActor
    func testSubmittedTimestampIsCapturedOnce() {
        let clock = IncrementingClock(start: 1_791_300_000)
        let viewModel = SubmittedViewModel(
            applicationId: "apply-demo",
            trackingNumber: nil,
            dataSource: ApplyReferenceDataSource(scenario: .inProgress),
            now: { clock.now() }
        )
        let firstRead = viewModel.submittedAt
        let secondRead = viewModel.submittedAt

        XCTAssertEqual(firstRead, secondRead)
        XCTAssertEqual(clock.callCount, 1)
    }

    @MainActor
    func testEmptySchemaSampleFormHasFallbackSectionAndCanComplete() async {
        let source = PreviewDataSource()
        let formId = "08e6603f-d197-4a60-98cd-d49acb1fc1fd"
        let progress = InMemoryFormProgressStore(
            completedSections: ["sample-application-in-progress/\(formId)": ["step-1"]]
        )
        let workspace = WorkspaceViewModel(
            applicationId: "sample-application-in-progress",
            dataSource: source,
            progressStore: progress
        )

        await workspace.load()

        XCTAssertEqual(
            workspace.requiredRows.first(where: { $0.id == formId })?.state,
            .inProgress(completedSteps: 1, totalSteps: 1)
        )

        let viewModel = FormScreenViewModel(
            applicationId: "sample-application-in-progress",
            formId: formId,
            dataSource: source,
            draftStore: SpyDraftStore(),
            progressStore: progress
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.currentFormStep?.sections.first?.id, "application")
        let outcome = await viewModel.continueTapped()
        XCTAssertEqual(outcome, .finished)
        let isComplete = await progress.isFormComplete(
            applicationId: "sample-application-in-progress",
            formId: formId
        )
        XCTAssertTrue(isComplete)
    }

    private func multiSectionStepDefinition() -> FormDefinition {
        func section(_ id: String) -> JSONValue {
            .object([
                "type": .string("section"),
                "name": .string(id),
                "label": .string(id),
                "children": .array([])
            ])
        }
        return FormDefinition(
            formId: "sf424",
            formName: "SF-424",
            shortFormName: "SF424_4_0",
            formJsonSchema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ]),
            formUiSchema: .array([
                section("submission_type"),
                section("applicant_information"),
                section("applicant_contact"),
                section("federal_agency"),
                section("areas_affected"),
                section("state_review")
            ])
        )
    }

    private func attachmentFormDefinition(array: Bool) -> FormDefinition {
        let attachmentSchema: JSONValue = array
            ? .object([
                "type": .string("array"),
                "minItems": .number(1),
                "items": .object([
                    "type": .string("string"),
                    "format": .string("uuid")
                ])
            ])
            : .object([
                "type": .string("string"),
                "format": .string("uuid")
            ])
        let field = JSONValue.object([
            "type": .string("field"),
            "definition": .string("/properties/supporting_attachment")
        ])
        let section = JSONValue.object([
            "type": .string("section"),
            "name": .string("attachments"),
            "label": .string("Attachments"),
            "children": .array([field])
        ])
        return FormDefinition(
            formId: "sf424",
            formName: "Attachment application",
            shortFormName: "ATTACHMENT",
            formJsonSchema: .object([
                "type": .string("object"),
                "properties": .object(["supporting_attachment": attachmentSchema]),
                "required": .array([.string("supporting_attachment")])
            ]),
            formUiSchema: .array([section])
        )
    }

    private func validValues(
        for step: FormStep,
        model: FormModel,
        startingWith initialValues: JSONValue
    ) -> JSONValue {
        let fields = step.sections.flatMap(\.fields)
        var values = initialValues
        for _ in 0...fields.count {
            for field in fields {
                guard field.isEditable,
                      FormValidator.isRequired(field, in: values, model: model),
                      !hasNonBlankValue(values.value(at: field.dataPath)) else {
                    continue
                }
                values.setValue(sampleValue(for: field), at: field.dataPath)
            }
        }

        for field in fields where field.isEditable {
            switch field.path {
            case "/properties/email":
                values.setValue(.string("dana@bluefieldchc.org"), at: field.dataPath)
            case "/properties/phone_number":
                values.setValue(.string("(304) 555-0142"), at: field.dataPath)
            case "/properties/applicant_type_code":
                if let option = field.options.first {
                    let value: JSONValue = field.kind == .multiSelect
                        ? .array([option.value])
                        : option.value
                    values.setValue(value, at: field.dataPath)
                }
            default:
                break
            }
        }
        return values
    }

    private func sampleValue(for field: FormField) -> JSONValue {
        if field.kind == .checkbox { return .bool(true) }
        if let option = field.options.first {
            return field.kind == .multiSelect ? .array([option.value]) : option.value
        }
        if field.textFormat == .date { return .string("2026-10-30") }
        if [.integer, .number, .currency].contains(field.textFormat) {
            return .number(1)
        }
        if field.kind == .fieldList { return .array([.object([:])]) }

        let title = field.title.lowercased()
        if title.contains("email") { return .string("dana@bluefieldchc.org") }
        if title.contains("phone") || title.contains("telephone") {
            return .string("(304) 555-0142")
        }
        if title.contains("zip") { return .string("22201") }
        if title.contains("ein") { return .string("12-3456789") }
        if title.contains("state") { return .string("VA") }
        if title.contains("city") { return .string("Arlington") }
        if title.contains("street") { return .string("123 Main Street") }
        return .string("Sample value")
    }

    private func hasNonBlankValue(_ value: JSONValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .null:
            return false
        case let .string(string):
            return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .array(values):
            return !values.isEmpty
        case let .object(values):
            return !values.isEmpty
        case .bool, .number:
            return true
        }
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

private actor SuspendingDraftStore: DraftStore {
    private(set) var savedValues: [JSONValue] = []
    private var firstSaveStarted = false
    private var firstSaveStartContinuation: CheckedContinuation<Void, Never>?
    private var firstSaveReleaseContinuation: CheckedContinuation<Void, Never>?

    func waitUntilFirstSaveStarts() async {
        guard !firstSaveStarted else { return }
        await withCheckedContinuation { firstSaveStartContinuation = $0 }
    }

    func releaseFirstSave() {
        firstSaveReleaseContinuation?.resume()
        firstSaveReleaseContinuation = nil
    }

    func loadDraft(applicationId: String, formId: String) async throws -> JSONValue? {
        nil
    }

    func saveDraft(_ value: JSONValue, applicationId: String, formId: String) async throws {
        if !firstSaveStarted {
            firstSaveStarted = true
            firstSaveStartContinuation?.resume()
            firstSaveStartContinuation = nil
            await withCheckedContinuation { firstSaveReleaseContinuation = $0 }
        }
        savedValues.append(value)
    }

    func removeDraft(applicationId: String, formId: String) async throws {}
}

private actor InMemoryApplyAttachmentStore: ApplyAttachmentStore {
    private var namesByForm: [String: [String: String]] = [:]
    private let shouldFail: Bool
    private var failuresRemaining: Int
    private let failingStoreCalls: Set<Int>
    private var storeCallCount = 0

    init(
        shouldFail: Bool = false,
        failuresRemaining: Int = 0,
        failingStoreCalls: Set<Int> = []
    ) {
        self.shouldFail = shouldFail
        self.failuresRemaining = failuresRemaining
        self.failingStoreCalls = failingStoreCalls
    }

    func store(
        _ url: URL,
        applicationId: String,
        formId: String
    ) async throws -> (id: String, name: String) {
        storeCallCount += 1
        if shouldFail || failuresRemaining > 0 || failingStoreCalls.contains(storeCallCount) {
            failuresRemaining = max(failuresRemaining - 1, 0)
            throw AttachmentStoreTestError.failed
        }
        let id = "demo-attachment-\(UUID().uuidString)"
        let name = url.lastPathComponent
        let key = "\(applicationId)/\(formId)"
        var names = namesByForm[key] ?? [:]
        names[id] = name
        namesByForm[key] = names
        return (id, name)
    }

    func names(applicationId: String, formId: String) async -> [String: String] {
        namesByForm["\(applicationId)/\(formId)"] ?? [:]
    }

    func remove(ids: Set<String>, applicationId: String, formId: String) async {
        let key = "\(applicationId)/\(formId)"
        var names = namesByForm[key] ?? [:]
        for id in ids {
            names.removeValue(forKey: id)
        }
        namesByForm[key] = names
    }

    func prune(keeping referenced: Set<String>, applicationId: String, formId: String) async {
        let key = "\(applicationId)/\(formId)"
        let names = namesByForm[key] ?? [:]
        namesByForm[key] = names.filter { referenced.contains($0.key) }
    }
}

private actor SuspendingApplyAttachmentStore: ApplyAttachmentStore {
    private var hasStartedStore = false
    private var storeStartedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var storedNames: [String: String] = [:]

    func waitUntilStoreStarts() async {
        guard !hasStartedStore else { return }
        await withCheckedContinuation { storeStartedContinuation = $0 }
    }

    func releaseStore() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func store(
        _ url: URL,
        applicationId: String,
        formId: String
    ) async throws -> (id: String, name: String) {
        hasStartedStore = true
        storeStartedContinuation?.resume()
        storeStartedContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
        let id = "demo-attachment-slow"
        let name = url.lastPathComponent
        storedNames[id] = name
        return (id, name)
    }

    func names(applicationId: String, formId: String) async -> [String: String] {
        storedNames
    }

    func remove(ids: Set<String>, applicationId: String, formId: String) async {
        for id in ids {
            storedNames.removeValue(forKey: id)
        }
    }

    func prune(keeping referenced: Set<String>, applicationId: String, formId: String) async {
        storedNames = storedNames.filter { referenced.contains($0.key) }
    }
}

private enum AttachmentStoreTestError: Error {
    case failed
}

private final class IncrementingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var timestamp: TimeInterval
    private var calls = 0

    init(start: TimeInterval) {
        timestamp = start
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        defer { timestamp += 1 }
        return Date(timeIntervalSince1970: timestamp)
    }
}

private actor SuspendingSaveDataSource: GrantsDataSource {
    private let base: ApplyReferenceDataSource
    private var firstSaveStarted = false
    private var firstSaveStartContinuation: CheckedContinuation<Void, Never>?
    private var firstSaveReleaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var receivedResponses: [JSONValue] = []

    init(base: ApplyReferenceDataSource) {
        self.base = base
    }

    func waitForFirstSave() async {
        guard !firstSaveStarted else { return }
        await withCheckedContinuation { firstSaveStartContinuation = $0 }
    }

    func releaseFirstSave() {
        firstSaveReleaseContinuation?.resume()
        firstSaveReleaseContinuation = nil
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
        try await base.organizations()
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
        receivedResponses.append(response)
        if receivedResponses.count == 1 {
            firstSaveStarted = true
            firstSaveStartContinuation?.resume()
            firstSaveStartContinuation = nil
            await withCheckedContinuation { firstSaveReleaseContinuation = $0 }
        }
        return try await base.saveForm(applicationId: applicationId, formId: formId, response: response)
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

private struct StubAuthorizer: SubmissionAuthorizing {
    let result: SubmissionAuthorization

    func authorize(reason: String) async -> SubmissionAuthorization {
        result
    }
}

private func persistedWarningValues(_ warnings: [ValidationWarning]) -> JSONValue {
    .array(warnings.map { warning in
        .object([
            "field": .string(warning.field),
            "message": .string(warning.message)
        ])
    })
}

private func applicationWithFormWarnings(
    _ application: Application,
    applicationId: String,
    formValidationWarnings: JSONValue
) -> Application {
    Application(
        applicationId: applicationId,
        applicationName: application.applicationName,
        applicationStatus: application.applicationStatus,
        competition: application.competition,
        organization: application.organization,
        applicationForms: application.applicationForms,
        formValidationWarnings: formValidationWarnings,
        intendsToAddOrganization: application.intendsToAddOrganization
    )
}

private func applicationWithoutOpportunityId(
    _ application: Application,
    closingDate: String? = nil
) -> Application {
    let original = application.competition
    let competition = Competition(
        competitionId: original.competitionId,
        competitionTitle: original.competitionTitle,
        openingDate: original.openingDate,
        closingDate: closingDate ?? original.closingDate,
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
