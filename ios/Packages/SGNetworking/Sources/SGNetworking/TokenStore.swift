import Foundation
import Security

public protocol TokenStore: Sendable {
    func load() -> String?
    func save(_ token: String) throws
    func clear()
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    public func save(_ token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        token = nil
    }
}

public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(
        service: String = "ai.cognition.demo.simplergrants",
        account: String = "sgg-token"
    ) {
        self.service = service
        self.account = account
    }

    public func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) throws {
        let data = Data(token.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw keychainError(status)
        }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw keychainError(addStatus)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}

public struct JWTClaims: Sendable, Equatable {
    public let userId: String
    public let issuedAt: Date
    public let sessionDuration: TimeInterval

    public var expiresAt: Date {
        issuedAt.addingTimeInterval(sessionDuration)
    }

    public init?(token: String) {
        let components = token.split(separator: ".")
        guard components.count >= 2 else { return nil }

        var payload = String(components[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let userId = object["user_id"] as? String,
            let issuedAt = object["iat"] as? NSNumber,
            let duration = object["session_duration_minutes"] as? NSNumber
        else {
            return nil
        }

        self.userId = userId
        self.issuedAt = Date(timeIntervalSince1970: issuedAt.doubleValue)
        sessionDuration = duration.doubleValue * 60
    }
}
