import Foundation
import SGModels

public protocol DraftStore: Sendable {
    func loadDraft(applicationId: String, formId: String) async throws -> JSONValue?
    func saveDraft(_ value: JSONValue, applicationId: String, formId: String) async throws
    func removeDraft(applicationId: String, formId: String) async throws
}

public actor FileDraftStore: DraftStore {
    private let directoryURL: URL

    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
            return
        }

        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.directoryURL = applicationSupportDirectory
            .appendingPathComponent("SimplerGrants/Drafts", isDirectory: true)
    }

    public func loadDraft(applicationId: String, formId: String) async throws -> JSONValue? {
        let url = fileURL(applicationId: applicationId, formId: formId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.sg.decode(JSONValue.self, from: data)
    }

    public func saveDraft(_ value: JSONValue, applicationId: String, formId: String) async throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.sg.encode(value)
        try data.write(to: fileURL(applicationId: applicationId, formId: formId), options: .atomic)
    }

    public func removeDraft(applicationId: String, formId: String) async throws {
        let url = fileURL(applicationId: applicationId, formId: formId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(applicationId: String, formId: String) -> URL {
        let identifier = Data("\(applicationId)\u{0}\(formId)".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directoryURL.appendingPathComponent("\(identifier).json")
    }
}
