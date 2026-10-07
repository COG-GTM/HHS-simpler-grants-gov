import Foundation
import SGModels

public struct DraftRecord: Codable, Sendable, Hashable {
    public let applicationId: String
    public let formId: String
    public let response: JSONValue
    public let updatedAt: Date
    public var needsSync: Bool
    public var lastError: String?

    public init(
        applicationId: String,
        formId: String,
        response: JSONValue,
        updatedAt: Date = Date(),
        needsSync: Bool = true,
        lastError: String? = nil
    ) {
        self.applicationId = applicationId
        self.formId = formId
        self.response = response
        self.updatedAt = updatedAt
        self.needsSync = needsSync
        self.lastError = lastError
    }
}

public protocol DraftStore: Sendable {
    func loadDraft(applicationId: String, formId: String) async throws -> JSONValue?
    func saveDraft(_ value: JSONValue, applicationId: String, formId: String) async throws
    func removeDraft(applicationId: String, formId: String) async throws
    func pendingDrafts() async throws -> [DraftRecord]
    func markSynced(applicationId: String, formId: String) async throws
    func markSynced(
        applicationId: String,
        formId: String,
        syncedResponse: JSONValue
    ) async throws
    func markFailed(applicationId: String, formId: String, message: String) async throws
    func markFailed(
        applicationId: String,
        formId: String,
        message: String,
        failedResponse: JSONValue
    ) async throws
}

public extension DraftStore {
    func pendingDrafts() async throws -> [DraftRecord] { [] }
    func markSynced(applicationId: String, formId: String) async throws {}
    func markSynced(
        applicationId: String,
        formId: String,
        syncedResponse: JSONValue
    ) async throws {
        try await markSynced(applicationId: applicationId, formId: formId)
    }
    func markFailed(applicationId: String, formId: String, message: String) async throws {}
    func markFailed(
        applicationId: String,
        formId: String,
        message: String,
        failedResponse: JSONValue
    ) async throws {
        try await markFailed(applicationId: applicationId, formId: formId, message: message)
    }
}

public actor FileDraftStore: DraftStore {
    private let directoryURL: URL
    private var cache: [String: DraftRecord] = [:]

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
        let key = cacheKey(applicationId: applicationId, formId: formId)
        if let record = cache[key] {
            return record.response
        }
        let url = fileURL(applicationId: applicationId, formId: formId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        if let record = try? JSONDecoder.sg.decode(DraftRecord.self, from: data) {
            cache[key] = record
            return record.response
        }
        let legacy = try JSONDecoder.sg.decode(JSONValue.self, from: data)
        let record = DraftRecord(
            applicationId: applicationId,
            formId: formId,
            response: legacy,
            updatedAt: modificationDate(for: url),
            needsSync: true
        )
        cache[key] = record
        return legacy
    }

    public func saveDraft(_ value: JSONValue, applicationId: String, formId: String) async throws {
        let record = DraftRecord(
            applicationId: applicationId,
            formId: formId,
            response: value,
            needsSync: true
        )
        try write(record)
    }

    public func removeDraft(applicationId: String, formId: String) async throws {
        let key = cacheKey(applicationId: applicationId, formId: formId)
        let url = fileURL(applicationId: applicationId, formId: formId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        cache.removeValue(forKey: key)
    }

    public func pendingDrafts() async throws -> [DraftRecord] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        var records: [DraftRecord] = []
        for url in urls where url.pathExtension == "json" {
            let data = try Data(contentsOf: url)
            if let record = try? JSONDecoder.sg.decode(DraftRecord.self, from: data) {
                cache[cacheKey(applicationId: record.applicationId, formId: record.formId)] = record
                if record.needsSync {
                    records.append(record)
                }
                continue
            }
            guard
                let (applicationId, formId) = decodeFileIdentifier(url.deletingPathExtension().lastPathComponent),
                let response = try? JSONDecoder.sg.decode(JSONValue.self, from: data)
            else {
                continue
            }
            let record = DraftRecord(
                applicationId: applicationId,
                formId: formId,
                response: response,
                updatedAt: modificationDate(for: url),
                needsSync: true
            )
            cache[cacheKey(applicationId: applicationId, formId: formId)] = record
            records.append(record)
        }
        return records.sorted { $0.updatedAt < $1.updatedAt }
    }

    public func markSynced(applicationId: String, formId: String) async throws {
        guard let record = try await record(applicationId: applicationId, formId: formId) else { return }
        try write(DraftRecord(
            applicationId: record.applicationId,
            formId: record.formId,
            response: record.response,
            updatedAt: record.updatedAt,
            needsSync: false,
            lastError: nil
        ))
    }

    public func markSynced(
        applicationId: String,
        formId: String,
        syncedResponse: JSONValue
    ) async throws {
        guard
            let record = try await record(applicationId: applicationId, formId: formId),
            record.response == syncedResponse
        else {
            return
        }
        try write(DraftRecord(
            applicationId: record.applicationId,
            formId: record.formId,
            response: record.response,
            updatedAt: record.updatedAt,
            needsSync: false,
            lastError: nil
        ))
    }

    public func markFailed(applicationId: String, formId: String, message: String) async throws {
        guard let record = try await record(applicationId: applicationId, formId: formId) else { return }
        try write(DraftRecord(
            applicationId: record.applicationId,
            formId: record.formId,
            response: record.response,
            updatedAt: record.updatedAt,
            needsSync: true,
            lastError: message
        ))
    }

    public func markFailed(
        applicationId: String,
        formId: String,
        message: String,
        failedResponse: JSONValue
    ) async throws {
        guard
            let record = try await record(applicationId: applicationId, formId: formId),
            record.response == failedResponse
        else {
            return
        }
        try write(DraftRecord(
            applicationId: record.applicationId,
            formId: record.formId,
            response: record.response,
            updatedAt: record.updatedAt,
            needsSync: true,
            lastError: message
        ))
    }

    private func record(applicationId: String, formId: String) async throws -> DraftRecord? {
        let key = cacheKey(applicationId: applicationId, formId: formId)
        if let record = cache[key] { return record }
        _ = try await loadDraft(applicationId: applicationId, formId: formId)
        return cache[key]
    }

    private func write(_ record: DraftRecord) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.sg.encode(record)
        try data.write(
            to: fileURL(applicationId: record.applicationId, formId: record.formId),
            options: .atomic
        )
        cache[cacheKey(applicationId: record.applicationId, formId: record.formId)] = record
    }

    private func fileURL(applicationId: String, formId: String) -> URL {
        directoryURL.appendingPathComponent("\(fileIdentifier(applicationId: applicationId, formId: formId)).json")
    }

    private func fileIdentifier(applicationId: String, formId: String) -> String {
        Data("\(applicationId)\u{0}\(formId)".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private func decodeFileIdentifier(_ identifier: String) -> (String, String)? {
        var base64 = identifier
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "+")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard
            let data = Data(base64Encoded: base64),
            let decoded = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let components = decoded.components(separatedBy: "\u{0}")
        guard components.count == 2 else { return nil }
        return (components[0], components[1])
    }

    private func cacheKey(applicationId: String, formId: String) -> String {
        "\(applicationId)\u{0}\(formId)"
    }

    private func modificationDate(for url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date ?? .distantPast
    }
}
