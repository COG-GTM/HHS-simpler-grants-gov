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
    public private(set) var sections: [FormSection] = []
    public var currentStep = 0
    public var values: JSONValue = .object([:]) {
        didSet {
            if !suppressAutosave, phase == .loaded {
                scheduleAutosave()
                invalidateProgressForFirstEdit()
            }
        }
    }
    public private(set) var errors: [FieldError] = []
    public private(set) var saveStatus: FormSaveStatus = .idle
    public private(set) var bannerMessage: String?
    public private(set) var prefill: [String: String] = [:]
    public private(set) var prefilledPaths: Set<String> = []
    public private(set) var isSyncing = false
    public private(set) var lastWarnings: [ValidationWarning] = []
    public private(set) var focusToken = 0

    private let dataSource: any GrantsDataSource
    private let draftStore: any DraftStore
    private let progressStore: any FormProgressStore
    private let validator: @Sendable (JSONValue, FormSection, FormModel) -> [FieldError]
    private let autosaveDelay: Duration
    private var autosaveTask: Task<Void, Never>?
    private var syncTail: Task<Bool, Never>?
    private var progressInvalidationTask: Task<Void, Never>?
    private var suppressAutosave = false
    private var didInvalidateProgressForEdit = false

    public init(
        applicationId: String,
        formId: String,
        dataSource: any GrantsDataSource,
        draftStore: any DraftStore,
        progressStore: any FormProgressStore,
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
        self.validator = validator
        self.autosaveDelay = autosaveDelay
    }

    public convenience init(
        applicationId: String,
        formId: String,
        dataSource: any GrantsDataSource,
        progressStore: any FormProgressStore,
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
            validator: validator,
            autosaveDelay: autosaveDelay
        )
    }

    public var stepCount: Int { sections.count }

    public var currentSection: FormSection? {
        guard sections.indices.contains(currentStep) else { return nil }
        return sections[currentStep]
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
            let formModel = try FormModel(definition: definition)
            let loadedDisplayName = ApplyFormStateLogic.displayName(
                formName: definition.formName,
                shortName: definition.shortFormName,
                formId: definition.formId
            )
            let loadedSections = formModel.sections.isEmpty
                ? [FormSection(id: "application", title: loadedDisplayName, fields: [])]
                : formModel.sections
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
                for section in formModel.sections {
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
                        guard let prefilledValue, !prefilledValue.isEmpty,
                              isMissingOrEmpty(loadedValues[property]) else {
                            continue
                        }
                        setTopLevelValue(prefilledValue, for: property, in: &loadedValues)
                        loadedPrefill[field.path] = prefilledValue
                        loadedPrefill[property] = prefilledValue
                        loadedPrefilledPaths.insert(field.path)
                    }
                }
            }

            suppressAutosave = true
            formDisplayName = loadedDisplayName
            shortName = definition.shortFormName ?? definition.formId
            model = formModel
            sections = loadedSections
            values = loadedValues
            prefill = loadedPrefill
            prefilledPaths = loadedPrefilledPaths
            let completed = await progressStore.completedSections(
                applicationId: applicationId,
                formId: definition.formId
            )
            currentStep = loadedSections.firstIndex { !completed.contains($0.id) } ?? 0
            errors = []
            saveStatus = .idle
            didInvalidateProgressForEdit = false
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
            let result = try await dataSource.saveForm(
                applicationId: applicationId,
                formId: formId,
                response: values
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
        guard let section = currentSection, let model else { return .finished }
        errors = validator(values, section, model)
        guard errors.isEmpty else {
            focusToken += 1
            return .stayed
        }
        guard await syncToServer() else { return .stayed }

        var completed = await progressStore.completedSections(
            applicationId: applicationId,
            formId: formId
        )
        completed.insert(section.id)
        await progressStore.setCompletedSections(
            completed,
            applicationId: applicationId,
            formId: formId
        )

        if currentStep >= sections.count - 1 {
            let invalidSections = sections.enumerated().compactMap { index, section in
                let sectionErrors = validator(values, section, model)
                return sectionErrors.isEmpty ? nil : (index, sectionErrors)
            }
            if let firstInvalid = invalidSections.first {
                currentStep = firstInvalid.0
                errors = firstInvalid.1
                focusToken += 1
                return .stayed
            }
            await progressStore.setFormComplete(true, applicationId: applicationId, formId: formId)
            return .finished
        }
        currentStep += 1
        errors = []
        return .advanced
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

    private func invalidateProgressForFirstEdit() {
        guard !didInvalidateProgressForEdit else { return }
        didInvalidateProgressForEdit = true
        let sectionId = currentSection?.id
        let progressStore = self.progressStore
        let applicationId = self.applicationId
        let formId = self.formId
        progressInvalidationTask = Task {
            await progressStore.setFormComplete(false, applicationId: applicationId, formId: formId)
            guard let sectionId else { return }
            var completed = await progressStore.completedSections(
                applicationId: applicationId,
                formId: formId
            )
            completed.remove(sectionId)
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

private func setTopLevelValue(_ string: String, for key: String, in value: inout JSONValue) {
    var object: [String: JSONValue]
    if case let .object(existing) = value {
        object = existing
    } else {
        object = [:]
    }
    object[key] = .string(string)
    value = .object(object)
}
