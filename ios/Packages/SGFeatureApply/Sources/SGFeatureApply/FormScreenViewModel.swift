import Foundation
import Observation
import SGCore
import SGForms
import SGModels

public enum FormSaveStatus: Sendable, Equatable {
    case idle
    case saving
    case saved
    case offline
    case failed
}

public enum ContinueOutcome: Sendable, Equatable {
    case stayed
    case advanced
    case finished
}

@MainActor
@Observable
public final class FormScreenViewModel {
    public let applicationId: String
    public let formId: String
    public private(set) var phase: ApplyLoadPhase = .loading
    public private(set) var formDisplayName = ""
    public private(set) var shortName = ""
    public private(set) var model: FormModel?
    public private(set) var steps: [FormStep] = []
    public var currentStep = 0
    public var values: JSONValue = .object([:]) {
        didSet {
            if !suppressAutosave, phase == .loaded {
                scheduleAutosave()
                invalidateProgressForEdit()
            }
        }
    }
    public private(set) var errors: [FieldError] = []
    public private(set) var sectionErrors: [String: [FieldError]] = [:]
    public private(set) var revealedSectionErrors: [String: [FieldError]] = [:]
    public private(set) var saveStatus: FormSaveStatus = .idle
    public private(set) var bannerMessage: String?
    public private(set) var prefill: [String: String] = [:]
    public private(set) var prefilledPaths: Set<String> = []
    public private(set) var attachmentNames: [String: String] = [:]
    public private(set) var isSyncing = false
    public private(set) var lastWarnings: [ValidationWarning] = []
    public private(set) var focusToken = 0

    private let dataSource: any GrantsDataSource
    private let draftStore: any DraftStore
    private let progressStore: any FormProgressStore
    private let attachmentStore: any ApplyAttachmentStore
    private let validator: @Sendable (JSONValue, FormSection, FormModel) -> [FieldError]
    private let autosaveDelay: Duration
    private var autosaveTask: Task<Void, Never>?
    private var syncTail: Task<Bool, Never>?
    private var progressInvalidationTask: Task<Void, Never>?
    private var suppressAutosave = false
    private var formCompleteInvalidated = false
    private var invalidatedStepIds: Set<String> = []

    public init(
        applicationId: String,
        formId: String,
        dataSource: any GrantsDataSource,
        draftStore: any DraftStore,
        progressStore: any FormProgressStore,
        attachmentStore: any ApplyAttachmentStore = FileApplyAttachmentStore(),
        validator: @escaping @Sendable (JSONValue, FormSection, FormModel) -> [FieldError] = {
            values, section, model in
            FormValidator.validate(values, section: section, model: model)
        },
        autosaveDelay: Duration = .milliseconds(800)
    ) {
        self.applicationId = applicationId
        self.formId = formId
        self.dataSource = dataSource
        self.draftStore = draftStore
        self.progressStore = progressStore
        self.attachmentStore = attachmentStore
        self.validator = validator
        self.autosaveDelay = autosaveDelay
    }

    public convenience init(
        applicationId: String,
        formId: String,
        dataSource: any GrantsDataSource,
        progressStore: any FormProgressStore,
        attachmentStore: any ApplyAttachmentStore = FileApplyAttachmentStore(),
        validator: @escaping @Sendable (JSONValue, FormSection, FormModel) -> [FieldError] = {
            values, section, model in
            FormValidator.validate(values, section: section, model: model)
        },
        autosaveDelay: Duration = .milliseconds(800)
    ) {
        self.init(
            applicationId: applicationId,
            formId: formId,
            dataSource: dataSource,
            draftStore: InMemoryApplyDraftStore(),
            progressStore: progressStore,
            attachmentStore: attachmentStore,
            validator: validator,
            autosaveDelay: autosaveDelay
        )
    }

    public var stepCount: Int { steps.count }

    public var currentFormStep: FormStep? {
        guard steps.indices.contains(currentStep) else { return nil }
        return steps[currentStep]
    }

    public var firstErrorSectionID: String? {
        currentFormStep?.sections.first {
            !(sectionErrors[$0.id] ?? []).isEmpty
        }?.id
    }

    public func load() async {
        if phase == .loaded {
            autosaveTask?.cancel()
            _ = await flushDraft()
        }
        if phase != .loaded { phase = .loading }
        do {
            let application = try await dataSource.application(id: applicationId)
            let applicationForm = application.applicationForms.first {
                $0.formId == formId || $0.applicationFormId == formId
            }
            let definition: FormDefinition
            if let applicationForm {
                definition = applicationForm.form
            } else {
                definition = try await dataSource.form(id: formId)
            }
            let restoredAttachmentNames = await attachmentStore.names(
                applicationId: applicationId,
                formId: formId
            )
            let formModel = try FormModel(definition: definition)
            let loadedDisplayName = ApplyFormStateLogic.displayName(
                formName: definition.formName,
                shortName: definition.shortFormName,
                formId: definition.formId
            )
            let fallbackSection = FormSection(
                id: "application",
                title: loadedDisplayName,
                fields: []
            )
            let loadedSections = formModel.sections.isEmpty
                ? [fallbackSection]
                : formModel.sections
            let loadedSteps = formModel.steps.isEmpty || formModel.sections.isEmpty
                ? [FormStep(
                    id: "application",
                    title: loadedDisplayName,
                    sections: [fallbackSection]
                )]
                : formModel.steps
            let draft = try? await draftStore.loadDraft(
                applicationId: applicationId,
                formId: definition.formId
            )
            let response = applicationForm?.applicationResponse ?? .object([:])
            let entity = application.organization?.samGovEntity
            var loadedValues = draft ?? response
            var loadedPrefill: [String: String] = [:]
            var loadedPrefilledPaths: Set<String> = []
            if let entity {
                for section in loadedSections {
                    for field in section.fields {
                        guard let property = formPropertyName(from: field.path) else { continue }
                        let prefilledValue: String?
                        switch property {
                        case "organization_name", "applicant_name", "legal_business_name", "legal_name":
                            prefilledValue = entity.legalBusinessName
                        case "sam_uei", "uei":
                            prefilledValue = entity.uei
                        default:
                            prefilledValue = nil
                        }
                        guard let prefilledValue, !prefilledValue.isEmpty else {
                            continue
                        }
                        let existingValue = loadedValues.value(at: field.dataPath)
                        if isMissingOrEmpty(existingValue) {
                            loadedValues.setValue(.string(prefilledValue), at: field.dataPath)
                        } else if existingValue != .string(prefilledValue) {
                            continue
                        }
                        loadedPrefill[field.path] = prefilledValue
                        loadedPrefill[field.dataPath.jsonPath] = prefilledValue
                        loadedPrefill[property] = prefilledValue
                        loadedPrefilledPaths.insert(field.path)
                    }
                }
            }

            suppressAutosave = true
            formDisplayName = loadedDisplayName
            shortName = ApplyFormStateLogic.navTitle(
                formName: definition.formName,
                shortName: definition.shortFormName,
                formId: definition.formId
            )
            model = formModel
            steps = loadedSteps
            values = loadedValues
            prefill = loadedPrefill
            prefilledPaths = loadedPrefilledPaths
            attachmentNames = restoredAttachmentNames
            sectionErrors = [:]
            revealedSectionErrors = [:]
            let storedProgressIds = await progressStore.completedSections(
                applicationId: applicationId,
                formId: definition.formId
            )
            let completedSteps = completedStepIds(stored: storedProgressIds, steps: loadedSteps)
            if completedSteps != storedProgressIds {
                await progressStore.setCompletedSections(
                    completedSteps,
                    applicationId: applicationId,
                    formId: definition.formId
                )
            }
            currentStep = loadedSteps.firstIndex { !completedSteps.contains($0.id) } ?? 0
            errors = []
            saveStatus = .idle
            formCompleteInvalidated = false
            invalidatedStepIds = []
            suppressAutosave = false
            phase = .loaded
        } catch {
            suppressAutosave = false
            phase = .failed("apply.error.load".localized(bundle: .module))
        }
    }

    public func scheduleAutosave() {
        autosaveTask?.cancel()
        saveStatus = .saving
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: autosaveDelay)
                try Task.checkCancellation()
                await self.saveDraftLocally()
            } catch is CancellationError {
            } catch {
                await self.setSaveFailure(error)
            }
        }
    }

    public func flushDraft() async -> Bool {
        if let progressInvalidationTask {
            await progressInvalidationTask.value
            self.progressInvalidationTask = nil
        }
        autosaveTask?.cancel()
        autosaveTask = nil
        saveStatus = .saving
        do {
            try await draftStore.saveDraft(values, applicationId: applicationId, formId: formId)
            saveStatus = .saved
            return true
        } catch {
            await setSaveFailure(error)
            return false
        }
    }

    @discardableResult
    public func syncToServer() async -> Bool {
        let previous = syncTail
        let task = Task { @MainActor [weak self] in
            if let previous {
                _ = await previous.value
            }
            guard let self else { return false }
            return await self.performSyncToServer()
        }
        syncTail = task
        return await task.value
    }

    private func performSyncToServer() async -> Bool {
        guard await flushDraft() else { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let response = values
            let result = try await dataSource.saveForm(
                applicationId: applicationId,
                formId: formId,
                response: response
            )
            try? await draftStore.markSynced(
                applicationId: applicationId,
                formId: formId,
                syncedResponse: response
            )
            lastWarnings = result.warnings
            await ApplyWarningsCache.shared.set(
                result.warnings,
                applicationId: applicationId,
                formId: formId
            )
            saveStatus = .saved
            bannerMessage = nil
            return true
        } catch let error as GrantsError {
            if error == .offline {
                saveStatus = .offline
                bannerMessage = "apply.form.offline".localized(bundle: .module)
            } else {
                saveStatus = .failed
                bannerMessage = "apply.form.sync_failed".localized(bundle: .module)
            }
            return false
        } catch {
            saveStatus = .failed
            bannerMessage = "apply.form.sync_failed".localized(bundle: .module)
            return false
        }
    }

    public func continueTapped() async -> ContinueOutcome {
        guard let step = currentFormStep, let model else { return .finished }
        let isLastStep = currentStep >= steps.count - 1
        if isLastStep {
            let allErrors = validationErrors(in: steps, model: model)
            let invalidStepIndices = steps.indices.filter { index in
                steps[index].sections.contains {
                    !(allErrors[$0.id] ?? []).isEmpty
                }
            }
            if let firstInvalidIndex = invalidStepIndices.first {
                currentStep = firstInvalidIndex
                let firstInvalidStep = steps[firstInvalidIndex]
                let visibleErrors = Dictionary(
                    uniqueKeysWithValues: firstInvalidStep.sections.map { section in
                        (section.id, allErrors[section.id] ?? [])
                    }
                )
                await setValidationErrors(visibleErrors, for: [firstInvalidStep])
                let invalidStepIds = Set(invalidStepIndices.map { steps[$0].id })
                var completed = await progressStore.completedSections(
                    applicationId: applicationId,
                    formId: formId
                )
                completed.subtract(invalidStepIds)
                await progressStore.setCompletedSections(
                    completed,
                    applicationId: applicationId,
                    formId: formId
                )
                focusToken += 1
                return .stayed
            }
            await setValidationErrors(validationErrors(in: step, model: model), for: [step])
        } else {
            await setValidationErrors(validationErrors(in: step, model: model), for: [step])
            guard errors.isEmpty else {
                focusToken += 1
                return .stayed
            }
        }

        guard await syncToServer() else { return .stayed }

        var completed = await progressStore.completedSections(
            applicationId: applicationId,
            formId: formId
        )
        completed.insert(step.id)
        await progressStore.setCompletedSections(
            completed,
            applicationId: applicationId,
            formId: formId
        )
        invalidatedStepIds.remove(step.id)

        if isLastStep {
            await progressStore.setFormComplete(true, applicationId: applicationId, formId: formId)
            return .finished
        }
        currentStep += 1
        errors = []
        sectionErrors = [:]
        revealedSectionErrors = [:]
        return .advanced
    }

    public func attach(_ request: FormAttachmentRequest) {
        Task { await attachFiles(request) }
    }

    func attachFiles(_ request: FormAttachmentRequest) async {
        guard !request.urls.isEmpty else { return }
        var attachments: [(id: String, name: String)] = []
        do {
            for url in request.urls {
                attachments.append(
                    try await attachmentStore.store(
                        url,
                        applicationId: applicationId,
                        formId: formId
                    )
                )
            }
        } catch {
            bannerMessage = "apply.form.attachment_failed".localized(bundle: .module)
            return
        }

        for attachment in attachments {
            attachmentNames[attachment.id] = attachment.name
        }
        let ids = attachments.map(\.id)
        if request.field.kind == .attachmentArray {
            let existing: [JSONValue]
            if case let .array(values)? = values.value(at: request.path) {
                existing = values
            } else {
                existing = []
            }
            values.setValue(.array(existing + ids.map(JSONValue.string)), at: request.path)
        } else if let id = ids.first {
            values.setValue(.string(id), at: request.path)
        }
    }

    private func validationErrors(in step: FormStep, model: FormModel) -> [String: [FieldError]] {
        Dictionary(
            uniqueKeysWithValues: step.sections.map { section in
                (section.id, validator(values, section, model))
            }
        )
    }

    private func validationErrors(in steps: [FormStep], model: FormModel) -> [String: [FieldError]] {
        var result: [String: [FieldError]] = [:]
        for step in steps {
            result.merge(validationErrors(in: step, model: model)) { _, latest in latest }
        }
        return result
    }

    private func setValidationErrors(
        _ sectionErrors: [String: [FieldError]],
        for visibleSteps: [FormStep]
    ) async {
        self.sectionErrors = sectionErrors
        errors = visibleSteps.flatMap { step in
            step.sections.flatMap { sectionErrors[$0.id] ?? [] }
        }
        let visibleSections = visibleSteps.flatMap(\.sections)
        let firstSectionWithErrors = visibleSections.first {
            !(sectionErrors[$0.id] ?? []).isEmpty
        }
        revealedSectionErrors = Dictionary(
            uniqueKeysWithValues: visibleSections
                .filter { $0.id != firstSectionWithErrors?.id }
                .map { ($0.id, sectionErrors[$0.id] ?? []) }
        )
        guard let firstSectionWithErrors,
              let firstErrors = sectionErrors[firstSectionWithErrors.id],
              !firstErrors.isEmpty else {
            return
        }
        await Task.yield()
        revealedSectionErrors[firstSectionWithErrors.id] = firstErrors
        await Task.yield()
    }

    public func saveDraftTapped() async -> Bool {
        await syncToServer()
    }

    public func backTapped() async {
        _ = await flushDraft()
        Task { [weak self] in
            _ = await self?.syncToServer()
        }
    }

    public func retry() async {
        _ = await syncToServer()
    }

    public func sceneDidBackground() async {
        _ = await syncToServer()
    }

    private func saveDraftLocally() async {
        do {
            try await draftStore.saveDraft(values, applicationId: applicationId, formId: formId)
            saveStatus = .saved
        } catch {
            await setSaveFailure(error)
        }
    }

    private func invalidateProgressForEdit() {
        let stepId = currentFormStep?.id
        let shouldInvalidateForm = !formCompleteInvalidated
        let shouldInvalidateStep = stepId.map { !invalidatedStepIds.contains($0) } ?? false
        guard shouldInvalidateForm || shouldInvalidateStep else { return }

        if shouldInvalidateForm {
            formCompleteInvalidated = true
        }
        if let stepId, shouldInvalidateStep {
            invalidatedStepIds.insert(stepId)
        }

        let previousTask = progressInvalidationTask
        let progressStore = self.progressStore
        let applicationId = self.applicationId
        let formId = self.formId
        progressInvalidationTask = Task {
            await previousTask?.value
            if shouldInvalidateForm {
                await progressStore.setFormComplete(false, applicationId: applicationId, formId: formId)
            }
            guard shouldInvalidateStep, let stepId else { return }
            var completed = await progressStore.completedSections(
                applicationId: applicationId,
                formId: formId
            )
            completed.remove(stepId)
            await progressStore.setCompletedSections(
                completed,
                applicationId: applicationId,
                formId: formId
            )
        }
    }

    private func setSaveFailure(_ error: Error) async {
        if (error as? GrantsError) == .offline {
            saveStatus = .offline
        } else {
            saveStatus = .failed
        }
    }
}

private func formPropertyName(from path: String) -> String? {
    let components = path.split(separator: "/").map(String.init)
    guard let index = components.firstIndex(of: "properties"),
          components.indices.contains(index + 1) else {
        return components.last
    }
    return components[index + 1]
}

private func isMissingOrEmpty(_ value: JSONValue?) -> Bool {
    guard let value else { return true }
    switch value {
    case .null:
        return true
    case let .string(string):
        return string.isEmpty
    default:
        return false
    }
}
