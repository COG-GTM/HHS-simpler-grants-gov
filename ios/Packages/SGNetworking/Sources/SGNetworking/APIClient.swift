import Foundation
import SGCore
import SGModels

public enum APIAuthRequirement: Sendable, Equatable {
    case userJWT
    case jwtOrAPIKey
    case apiKey
}

public actor APIClient {
    private let baseURL: URL
    private let apiKey: String?
    private let tokenStore: any TokenStore
    private let session: URLSession
    private let now: @Sendable () -> Date
    private var refreshTask: Task<Void, Error>?
    private var refreshedToken: String?
    private var refreshedAt: Date?

    public init(
        baseURL: URL,
        apiKey: String?,
        tokenStore: any TokenStore,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.tokenStore = tokenStore
        self.session = session
        self.now = now
    }

    public func userId() throws -> String {
        guard let token = tokenStore.load(), let claims = JWTClaims(token: token) else {
            throw GrantsError.unauthorized
        }
        return claims.userId
    }

    public func data(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        requiresUser: Bool = false
    ) async throws -> Data {
        try await data(
            path: path,
            method: method,
            body: body,
            authRequirement: requiresUser ? .userJWT : .jwtOrAPIKey
        )
    }

    public func data(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        authRequirement: APIAuthRequirement
    ) async throws -> Data {
        let token = try requestToken(for: authRequirement)
        if authRequirement != .apiKey,
           let token,
           let claims = JWTClaims(token: token),
           effectiveExpiry(for: token, claims: claims).timeIntervalSince(now()) <= 5 * 60 {
            try await refreshOrExpireSession(expectedToken: token)
        }

        return try await perform(
            path: path,
            method: method,
            body: body,
            authRequirement: authRequirement,
            retryAfterRefresh: true
        )
    }

    private func perform(
        path: String,
        method: String,
        body: Data?,
        authRequirement: APIAuthRequirement,
        retryAfterRefresh: Bool,
        clearSessionOnUnauthorized: Bool = false
    ) async throws -> Data {
        let token = try requestToken(for: authRequirement)
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token {
            request.setValue(token, forHTTPHeaderField: "X-SGG-Token")
        } else if let apiKey,
                  authRequirement != .userJWT,
                  isLoopbackHost(baseURL.host) {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if isOffline(error.code) { throw GrantsError.offline }
            throw GrantsError.server(status: error.errorCode, message: error.localizedDescription)
        } catch {
            throw GrantsError.server(status: 0, message: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GrantsError.server(status: 0, message: "Invalid server response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401,
               let token,
               authRequirement != .apiKey,
               retryAfterRefresh {
                try await refreshOrExpireSession(expectedToken: token)
                return try await perform(
                    path: path,
                    method: method,
                    body: body,
                    authRequirement: authRequirement,
                    retryAfterRefresh: false,
                    clearSessionOnUnauthorized: true
                )
            }
            if http.statusCode == 401 {
                if clearSessionOnUnauthorized, let token {
                    expireSession(ifCurrent: token)
                }
                throw GrantsError.unauthorized
            }
            if http.statusCode == 403 {
                throw GrantsError.unauthorized
            }
            if http.statusCode == 404 {
                throw GrantsError.notFound
            }
            throw serverError(status: http.statusCode, data: data)
        }
        return data
    }

    private func refreshToken() async throws {
        if let refreshTask {
            try await refreshTask.value
            return
        }
        guard tokenStore.load() != nil else {
            throw GrantsError.unauthorized
        }

        let task = Task { try await self.performRefresh() }
        refreshTask = task
        do {
            try await task.value
            refreshTask = nil
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func refreshOrExpireSession(expectedToken: String) async throws {
        do {
            try await refreshToken()
        } catch let error as GrantsError {
            if error == .unauthorized {
                expireSession(ifCurrent: expectedToken)
            }
            throw error
        }
    }

    private func performRefresh() async throws {
        let token = tokenStore.load()
        let response = try await perform(
            path: "/v1/users/token/refresh",
            method: "POST",
            body: nil,
            authRequirement: .userJWT,
            retryAfterRefresh: false
        )
        _ = response
        guard let token, tokenStore.load() == token, JWTClaims(token: token) != nil else {
            throw GrantsError.unauthorized
        }
        refreshedToken = token
        refreshedAt = now()
    }

    private func requestToken(for requirement: APIAuthRequirement) throws -> String? {
        switch requirement {
        case .userJWT:
            guard let token = tokenStore.load() else { throw GrantsError.unauthorized }
            return token
        case .jwtOrAPIKey:
            if let token = tokenStore.load() {
                return token
            }
            return nil
        case .apiKey:
            guard isLoopbackHost(baseURL.host), apiKey != nil else {
                throw GrantsError.unauthorized
            }
            return nil
        }
    }

    private func effectiveExpiry(for token: String, claims: JWTClaims) -> Date {
        guard refreshedToken == token, let refreshedAt else { return claims.expiresAt }
        return refreshedAt.addingTimeInterval(claims.sessionDuration)
    }

    private func expireSession(ifCurrent token: String) {
        guard tokenStore.load() == token else { return }
        tokenStore.clear()
        NotificationCenter.default.post(name: .sgSessionExpired, object: nil)
    }

    private func serverError(status: Int, data: Data) -> GrantsError {
        let envelope = try? JSONDecoder.sg.decode(ErrorEnvelope.self, from: data)
        let detail = envelope?.errors?.first?.message
        let message = [envelope?.message, detail]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return .server(status: status, message: message.isEmpty ? nil : message)
    }

    private func isLoopbackHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func isOffline(_ code: URLError.Code) -> Bool {
        [
            .notConnectedToInternet,
            .networkConnectionLost,
            .cannotConnectToHost,
            .cannotFindHost,
            .timedOut,
            .dataNotAllowed,
            .internationalRoamingOff
        ].contains(code)
    }
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let message: String
    }

    let message: String?
    let errors: [Detail]?
}
