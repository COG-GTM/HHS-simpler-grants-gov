import AuthenticationServices
import Foundation
import SGModels
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public protocol WebAuthenticating: Sendable {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

public struct LoginGovAuthenticator: Authenticating {
    private static let cachedProfileKey = "sg.cached_user_profile"

    private struct CachedProfile: Codable {
        let userId: String
        let profile: UserProfile
    }

    private let dataSource: any GrantsDataSource
    private let testToken: String?
    private let baseURL: URL
    private let tokenStore: any TokenStore
    private let webAuthenticator: any WebAuthenticating

    public init(dataSource: any GrantsDataSource, testToken: String? = nil) {
        let store: any TokenStore
        if let liveDataSource = dataSource as? LiveDataSource {
            store = liveDataSource.tokenStore
            if let testToken {
                try? store.save(testToken)
            }
        } else {
            store = InMemoryTokenStore(token: testToken)
        }
        self.dataSource = dataSource
        self.testToken = testToken
        baseURL = (dataSource as? LiveDataSource)?.baseURL
            ?? URL(string: "http://127.0.0.1:8080")!
        tokenStore = store
        webAuthenticator = ASWebAuthenticationSessionAuthenticator()
    }

    public init(
        baseURL: URL,
        dataSource: any GrantsDataSource,
        tokenStore: any TokenStore,
        testToken: String? = nil,
        webAuthenticator: any WebAuthenticating = ASWebAuthenticationSessionAuthenticator()
    ) {
        self.baseURL = baseURL
        self.dataSource = dataSource
        self.tokenStore = tokenStore
        self.testToken = testToken
        self.webAuthenticator = webAuthenticator
    }

    public func signIn(pivRequired: Bool) async throws -> UserProfile {
        var components = URLComponents(url: baseURL.appending(path: "/v1/users/login"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client", value: "ios"),
            pivRequired ? URLQueryItem(name: "piv_required", value: "true") : nil
        ].compactMap { $0 }
        guard let loginURL = components.url else {
            throw GrantsError.server(status: 500, message: "The sign-in URL is invalid.")
        }

        let callback = try await webAuthenticator.authenticate(url: loginURL, callbackScheme: "simplergrants")
        switch LoginCallback.parse(callback) {
        case let .success(token, _):
            do {
                try tokenStore.save(token)
            } catch {
                throw GrantsError.server(status: 500, message: error.localizedDescription)
            }
            let user = try await dataSource.currentUser()
            saveCachedProfile(user)
            return user
        case let .failure(description, _):
            throw GrantsError.server(status: 401, message: description)
        case .invalid:
            throw GrantsError.server(status: 401, message: "The sign-in response was invalid.")
        }
    }

    public func restore() async -> UserProfile? {
        if let testToken, !testToken.isEmpty {
            try? tokenStore.save(testToken)
        }
        guard tokenStore.load() != nil else { return nil }

        do {
            let user = try await dataSource.currentUser()
            saveCachedProfile(user)
            return user
        } catch GrantsError.unauthorized {
            tokenStore.clear()
            return nil
        } catch GrantsError.offline {
            return loadCachedProfile()
        } catch {
            return nil
        }
    }

    public func signOut() async {
        let client = APIClient(baseURL: baseURL, apiKey: nil, tokenStore: tokenStore)
        _ = try? await client.data(
            path: "/v1/users/token/logout",
            method: "POST",
            authRequirement: .userJWT
        )
        tokenStore.clear()
        UserDefaults.standard.removeObject(forKey: Self.cachedProfileKey)
    }

    private func saveCachedProfile(_ profile: UserProfile) {
        guard
            let token = tokenStore.load(),
            let userId = JWTClaims(token: token)?.userId,
            let data = try? JSONEncoder.sg.encode(CachedProfile(userId: userId, profile: profile))
        else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.cachedProfileKey)
    }

    private func loadCachedProfile() -> UserProfile? {
        guard
            let token = tokenStore.load(),
            let userId = JWTClaims(token: token)?.userId,
            let data = UserDefaults.standard.data(forKey: Self.cachedProfileKey),
            let cached = try? JSONDecoder.sg.decode(CachedProfile.self, from: data),
            cached.userId == userId,
            cached.profile.id == cached.userId
        else {
            return nil
        }
        return cached.profile
    }
}

public final class ASWebAuthenticationSessionAuthenticator: NSObject, WebAuthenticating,
    ASWebAuthenticationPresentationContextProviding, @unchecked Sendable
{
    private var authenticationSession: ASWebAuthenticationSession?

    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.authenticationSession = nil
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GrantsError.server(
                        status: 401,
                        message: "The sign-in response was missing."
                    ))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            authenticationSession = session
            guard session.start() else {
                authenticationSession = nil
                continuation.resume(throwing: GrantsError.server(
                    status: 500,
                    message: "The sign-in session could not start."
                ))
                return
            }
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow()
        #elseif canImport(AppKit)
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
        #else
        ASPresentationAnchor()
        #endif
    }
}
