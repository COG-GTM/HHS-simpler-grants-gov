import Foundation

public protocol FormProgressStore: Sendable {
    func completedSections(applicationId: String, formId: String) async -> Set<String>
    func setCompletedSections(_ sections: Set<String>, applicationId: String, formId: String) async
    func isFormComplete(applicationId: String, formId: String) async -> Bool
    func setFormComplete(_ complete: Bool, applicationId: String, formId: String) async
}

public actor InMemoryFormProgressStore: FormProgressStore {
    private var sections: [String: Set<String>]
    private var completeForms: Set<String>

    public init(
        completedSections: [String: Set<String>] = [:],
        completeForms: Set<String> = []
    ) {
        sections = completedSections
        self.completeForms = completeForms
    }

    public func completedSections(applicationId: String, formId: String) -> Set<String> {
        sections[key(applicationId: applicationId, formId: formId)] ?? []
    }

    public func setCompletedSections(
        _ sections: Set<String>,
        applicationId: String,
        formId: String
    ) {
        self.sections[key(applicationId: applicationId, formId: formId)] = sections
    }

    public func isFormComplete(applicationId: String, formId: String) -> Bool {
        completeForms.contains(key(applicationId: applicationId, formId: formId))
    }

    public func setFormComplete(_ complete: Bool, applicationId: String, formId: String) {
        let identifier = key(applicationId: applicationId, formId: formId)
        if complete {
            completeForms.insert(identifier)
        } else {
            completeForms.remove(identifier)
        }
    }

    private func key(applicationId: String, formId: String) -> String {
        "\(applicationId)/\(formId)"
    }
}

public final class UserDefaultsFormProgressStore: FormProgressStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func completedSections(applicationId: String, formId: String) async -> Set<String> {
        synchronized {
            Set(defaults.stringArray(forKey: sectionsKey(applicationId: applicationId, formId: formId)) ?? [])
        }
    }

    public func setCompletedSections(
        _ sections: Set<String>,
        applicationId: String,
        formId: String
    ) async {
        synchronized {
            defaults.set(
                sections.sorted(),
                forKey: sectionsKey(applicationId: applicationId, formId: formId)
            )
        }
    }

    public func isFormComplete(applicationId: String, formId: String) async -> Bool {
        synchronized {
            defaults.bool(forKey: completeKey(applicationId: applicationId, formId: formId))
        }
    }

    public func setFormComplete(
        _ complete: Bool,
        applicationId: String,
        formId: String
    ) async {
        synchronized {
            defaults.set(complete, forKey: completeKey(applicationId: applicationId, formId: formId))
        }
    }

    private func synchronized<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    private func sectionsKey(applicationId: String, formId: String) -> String {
        "sg.apply.progress.\(applicationId).\(formId).sections"
    }

    private func completeKey(applicationId: String, formId: String) -> String {
        "sg.apply.progress.\(applicationId).\(formId).complete"
    }
}
