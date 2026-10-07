import SGCore
import SGModels

actor InMemoryApplyDraftStore: DraftStore {
    private var drafts: [String: JSONValue] = [:]

    func loadDraft(applicationId: String, formId: String) async throws -> JSONValue? {
        drafts[key(applicationId: applicationId, formId: formId)]
    }

    func saveDraft(_ value: JSONValue, applicationId: String, formId: String) async throws {
        drafts[key(applicationId: applicationId, formId: formId)] = value
    }

    func removeDraft(applicationId: String, formId: String) async throws {
        drafts.removeValue(forKey: key(applicationId: applicationId, formId: formId))
    }

    private func key(applicationId: String, formId: String) -> String {
        "\(applicationId)/\(formId)"
    }
}
