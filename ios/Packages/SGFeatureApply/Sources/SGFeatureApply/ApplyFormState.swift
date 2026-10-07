import SGForms
import SGModels

public enum ApplyFormState: Hashable, Sendable {
    case notStarted
    case inProgress(completedSteps: Int, totalSteps: Int)
    case complete
}

func completedStepIds(stored: Set<String>, steps: [FormStep]) -> Set<String> {
    let stepIds = Set(steps.map(\.id))
    let migratedStepIds: [String] = steps.compactMap { step -> String? in
        guard !step.sectionIDs.isEmpty, Set(step.sectionIDs).isSubset(of: stored) else { return nil }
        return step.id
    }
    return stored.intersection(stepIds).union(migratedStepIds)
}

public struct ApplyFormRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let applicationFormId: String
    public let displayName: String
    public let shortName: String
    public let isRequired: Bool
    public let state: ApplyFormState

    public init(
        id: String,
        applicationFormId: String,
        displayName: String,
        shortName: String,
        isRequired: Bool,
        state: ApplyFormState
    ) {
        self.id = id
        self.applicationFormId = applicationFormId
        self.displayName = displayName
        self.shortName = shortName
        self.isRequired = isRequired
        self.state = state
    }
}

public enum ApplyFormStateLogic {
    public static func displayName(formName: String?, shortName: String?) -> String {
        displayName(formName: formName, shortName: shortName, formId: "")
    }

    public static func state(
        serverStatus: String,
        response: JSONValue,
        hasDraft: Bool,
        hasUnsyncedDraft: Bool,
        completedStepIds: Set<String>,
        stepIds: [String],
        locallyComplete: Bool
    ) -> ApplyFormState {
        let serverComplete = serverStatus.caseInsensitiveCompare("complete") == .orderedSame
        if locallyComplete || (serverComplete && !hasUnsyncedDraft) {
            return .complete
        }
        let total = max(stepIds.count, 1)
        let done = completedStepIds.intersection(stepIds).count
        if done > 0 || hasDraft || isNonEmptyObject(response) {
            return .inProgress(completedSteps: done, totalSteps: total)
        }
        return .notStarted
    }

    public static func displayName(
        formName: String?,
        shortName: String?,
        formId: String
    ) -> String {
        guard let formName, let shortName else {
            return formName ?? shortName ?? formId
        }
        let suffix = "(\(shortName))"
        guard formName.hasSuffix(suffix) else { return formName }
        return "\(shortName) \(formName.dropLast(suffix.count).trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private static func isNonEmptyObject(_ value: JSONValue) -> Bool {
        if case let .object(values) = value {
            return !values.isEmpty
        }
        return false
    }
}
