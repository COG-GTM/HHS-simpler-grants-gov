import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SGCore
import SGModels
import SGNetworking
import XCTest

final class LiveSmokeTests: XCTestCase {
    func testLoginSearchDetailStartApplicationAndFetchForm() async throws {
        guard ProcessInfo.processInfo.environment["SG_LIVE_API"] == "1" else {
            throw XCTSkip("Set SG_LIVE_API=1 to run against the local API.")
        }

        let baseURL = URL(string: "http://127.0.0.1:8080")!
        let token = try await login(baseURL: baseURL)
        let dataSource = LiveDataSource(
            baseURL: baseURL,
            apiKey: "local-dev-api-key",
            tokenStore: InMemoryTokenStore(token: token)
        )
        let search = try await dataSource.searchOpportunities(SearchRequest())
        XCTAssertFalse(search.data.isEmpty)

        let detail = try await dataSource.opportunity(id: "cc76e832-03d8-41b3-bc17-639193e96de0")
        let competition = try XCTUnwrap(detail.competitions.first {
            $0.isOpen && $0.isSimplerGrantsEnabled && !$0.competitionForms.isEmpty
        })
        let applicationId = try await dataSource.startApplication(
            competitionId: competition.competitionId,
            name: "iOS Live Smoke",
            organizationId: "47d95649-c70d-44d9-ae78-68bf848e32f8"
        )
        let application = try await dataSource.application(id: applicationId)
        XCTAssertEqual(application.applicationId, applicationId)

        let formId = try XCTUnwrap(competition.competitionForms.first?.form.formId)
        let form = try await dataSource.form(id: formId)
        XCTAssertEqual(form.formId, formId)
    }

    private func login(baseURL: URL) async throws -> String {
        let redirectDelegate = MockLoginRedirectDelegate()
        let session = URLSession(
            configuration: .ephemeral,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        var components = URLComponents(url: baseURL.appending(path: "/v1/users/login"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "client", value: "ios")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)

        if let callbackURL = redirectDelegate.callbackURL,
           case let .success(token, _) = LoginCallback.parse(callbackURL) {
            return token
        }
        if let http = response as? HTTPURLResponse,
           let responseURL = http.url,
           let token = token(in: responseURL) {
            return token
        }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let token = token(in: object) {
            return token
        }
        throw GrantsError.decoding("The local login flow did not return a token.")
    }

    private func token(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value
    }

    private func token(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let token = dictionary["token"] as? String {
                return token
            }
            for value in dictionary.values {
                if let token = token(in: value) {
                    return token
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let token = token(in: value) {
                    return token
                }
            }
        }
        return nil
    }
}

private final class MockLoginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCallbackURL: URL?

    var callbackURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return storedCallbackURL
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url else {
            completionHandler(request)
            return
        }
        if url.scheme == "simplergrants" {
            lock.lock()
            storedCallbackURL = url
            lock.unlock()
            completionHandler(nil)
            return
        }
        guard url.host == "127.0.0.1", url.port == 5001, url.path.contains("/authorize") else {
            completionHandler(request)
            return
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            completionHandler(request)
            return
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "login" }
        queryItems.append(URLQueryItem(name: "login", value: "one_org_user"))
        components.queryItems = queryItems
        var authenticatedRequest = request
        authenticatedRequest.url = components.url
        completionHandler(authenticatedRequest)
    }
}
