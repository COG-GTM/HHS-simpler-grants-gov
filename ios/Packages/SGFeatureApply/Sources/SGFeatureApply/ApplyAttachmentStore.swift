import Foundation

public protocol ApplyAttachmentStore: Sendable {
    func store(
        _ url: URL,
        applicationId: String,
        formId: String
    ) async throws -> (id: String, name: String)

    func names(applicationId: String, formId: String) async -> [String: String]
}

public actor FileApplyAttachmentStore: ApplyAttachmentStore {
    private let fileManager: FileManager
    private let applicationSupportURL: URL?

    public init() {
        fileManager = .default
        applicationSupportURL = nil
    }

    init(applicationSupportURL: URL, fileManager: FileManager = .default) {
        self.applicationSupportURL = applicationSupportURL
        self.fileManager = fileManager
    }

    public func store(
        _ url: URL,
        applicationId: String,
        formId: String
    ) async throws -> (id: String, name: String) {
        let name = url.lastPathComponent
        guard !name.isEmpty else { throw ApplyAttachmentStoreError.invalidName }
        let formDirectory = try formDirectoryURL(
            applicationId: applicationId,
            formId: formId,
            create: true
        )
        let id = "demo-attachment-\(UUID().uuidString)"
        let attachmentDirectory = formDirectory.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(
            at: attachmentDirectory,
            withIntermediateDirectories: true
        )

        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let destination = attachmentDirectory.appendingPathComponent(name)
            try fileManager.copyItem(at: url, to: destination)

            let namesURL = formDirectory.appendingPathComponent("names.json")
            var attachmentNames: [String: String]
            if fileManager.fileExists(atPath: namesURL.path) {
                let data = try Data(contentsOf: namesURL)
                attachmentNames = try JSONDecoder().decode([String: String].self, from: data)
            } else {
                attachmentNames = [:]
            }
            attachmentNames[id] = name

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(attachmentNames).write(to: namesURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: attachmentDirectory)
            throw error
        }

        return (id, name)
    }

    public func names(applicationId: String, formId: String) async -> [String: String] {
        guard let formDirectory = try? formDirectoryURL(
            applicationId: applicationId,
            formId: formId,
            create: false
        ) else {
            return [:]
        }
        let namesURL = formDirectory.appendingPathComponent("names.json")
        guard let data = try? Data(contentsOf: namesURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func formDirectoryURL(
        applicationId: String,
        formId: String,
        create: Bool
    ) throws -> URL {
        guard Self.isSafePathComponent(applicationId), Self.isSafePathComponent(formId) else {
            throw ApplyAttachmentStoreError.invalidPath
        }
        let supportDirectory = try applicationSupportURL
            ?? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: create
            )
        let formDirectory = supportDirectory
            .appendingPathComponent("SGApply", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent(applicationId, isDirectory: true)
            .appendingPathComponent(formId, isDirectory: true)
        if create {
            try fileManager.createDirectory(
                at: formDirectory,
                withIntermediateDirectories: true
            )
        }
        return formDirectory
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
    }
}

private enum ApplyAttachmentStoreError: Error {
    case invalidName
    case invalidPath
}
