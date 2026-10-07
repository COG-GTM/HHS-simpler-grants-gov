import Foundation
import SGCore
import SGModels
import SGNetworking
import Security
import XCTest

final class JWTClaimsTests: XCTestCase {
    func testParsesBase64URLJWTClaimsWithoutVerifyingSignature() throws {
        let issuedAt = 1_700_000_000
        let token = makeToken(userId: "user-1", issuedAt: issuedAt, duration: 30)
        let claims = try XCTUnwrap(JWTClaims(token: token))
        XCTAssertEqual(claims.userId, "user-1")
        XCTAssertEqual(claims.issuedAt.timeIntervalSince1970, Double(issuedAt))
        XCTAssertEqual(claims.sessionDuration, 30 * 60)
        XCTAssertNil(JWTClaims(token: "not-a-jwt"))
    }
}

final class LoginCallbackTests: XCTestCase {
    func testParsesLoginSuccessAndFailureCallbacks() throws {
        XCTAssertEqual(
            LoginCallback.parse(try XCTUnwrap(URL(string: "simplergrants://auth/callback?message=success&token=fake&is_user_new=0"))),
            .success(token: "fake", isUserNew: false)
        )
        XCTAssertEqual(
            LoginCallback.parse(try XCTUnwrap(URL(string: "simplergrants://auth/callback?message=success&token=fake&is_user_new=1"))),
            .success(token: "fake", isUserNew: true)
        )
        XCTAssertEqual(
            LoginCallback.parse(try XCTUnwrap(URL(string: "simplergrants://auth/callback?message=error&error_description=Denied"))),
            .failure(description: "Denied", pivRequired: false)
        )
        XCTAssertEqual(
            LoginCallback.parse(try XCTUnwrap(URL(string: "simplergrants://auth/callback?message=error&login_piv_required_error=required"))),
            .failure(description: "Sign in could not be completed.", pivRequired: true)
        )
        XCTAssertEqual(
            LoginCallback.parse(try XCTUnwrap(URL(string: "https://example.org/auth/callback?message=success&token=x"))),
            .invalid
        )
        XCTAssertEqual(
            LoginCallback.parse(try XCTUnwrap(URL(string: "simplergrants://auth/callback?message=success"))),
            .invalid
        )
    }
}

final class TokenStoreTests: XCTestCase {
    func testInMemoryStoreRoundTrip() throws {
        let store = InMemoryTokenStore()
        XCTAssertNil(store.load())
        try store.save("first")
        try store.save("second")
        XCTAssertEqual(store.load(), "second")
        store.clear()
        XCTAssertNil(store.load())
    }

    func testKeychainRoundTrip() throws {
        let service = "ai.cognition.demo.simplergrants.tests.\(UUID().uuidString)"
        let store = KeychainTokenStore(service: service, account: "token")
        defer { store.clear() }

        do {
            try store.save("first")
            XCTAssertEqual(store.load(), "first")
            try store.save("second")
            XCTAssertEqual(store.load(), "second")
            store.clear()
            XCTAssertNil(store.load())
        } catch {
            let status = (error as NSError).code
            if status == Int(errSecMissingEntitlement) {
                throw XCTSkip("Keychain access requires an iOS simulator entitlement.")
            }
            throw error
        }
    }
}

final class LiveDataSourceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testEndpointPathsMethodsHeadersBodiesAndDecoding() async throws {
        let session = makeSession()
        let store = InMemoryTokenStore()
        let dataSource = LiveDataSource(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: "local-dev-api-key",
            tokenStore: store,
            session: session
        )
        StubURLProtocol.install { request in
            let path = request.url!.path
            switch path {
            case "/v1/opportunities/search":
                return (200, """
                {"message":"Success","data":[],"pagination_info":{"page_offset":1,"page_size":10,"total_pages":0,"total_records":0},"facet_counts":{}}
                """)
            case "/v1/opportunities/opp-1":
                return (200, """
                {"data":{"opportunity_id":"opp-1","opportunity_status":"posted","summary":{},"opportunity_assistance_listings":[],"attachments":[],"competitions":[]}}
                """)
            case "/v1/users/user-1":
                return (200, #"{"data":{"user_id":"user-1","email":"demo@example.org","profile":{}}}"#)
            case "/v1/users/user-1/organizations", "/v1/users/user-1/applications",
                "/v1/users/user-1/saved-opportunities/list",
                "/alpha/applications/app-1/submissions":
                return (200, #"{"data":[],"pagination_info":{"total_pages":1}}"#)
            case "/alpha/applications/start":
                return (200, #"{"data":{"application_id":"app-1"}}"#)
            case "/alpha/applications/app-1":
                return (200, """
                {"data":{"application_id":"app-1","application_name":"Draft","application_status":"in_progress","competition":{"competition_id":"comp-1","is_open":true,"is_simpler_grants_enabled":true,"open_to_applicants":[],"competition_forms":[],"competition_instructions":[],"opportunity":{"opportunity_id":"opp-1"}},"application_forms":[],"form_validation_warnings":{}}}
                """)
            case "/alpha/forms/form-1":
                return (200, #"{"data":{"form_id":"form-1","form_json_schema":{},"form_ui_schema":[]}}"#)
            case "/alpha/applications/app-1/forms/form-1":
                return (200, """
                {"message":"Saved","data":{"application_form_id":"record-1","form_id":"form-1","form":{"form_id":"form-1","form_json_schema":{},"form_ui_schema":[]},"application_response":{"answer":"yes"},"application_form_status":"in_progress","is_required":true},"warnings":[{"field":"answer","message":"Check the answer","type":"warning"}]}
                """)
            case "/alpha/applications/app-1/submit":
                return (200, #"{"message":"Success","data":{}}"#)
            case "/v1/users/user-1/saved-opportunities":
                return (200, #"{"message":"Saved","data":{}}"#)
            case "/v1/users/user-1/saved-opportunities/opp-1":
                return (204, "")
            default:
                return (404, #"{"message":"Unexpected path","data":{}}"#)
            }
        }

        let search = try await dataSource.searchOpportunities(SearchRequest())
        XCTAssertTrue(search.data.isEmpty)
        XCTAssertEqual(search.paginationInfo.totalPages, 0)
        let detail = try await dataSource.opportunity(id: "opp-1")
        XCTAssertTrue(detail.competitions.isEmpty)
        let apiKeyRequests = StubURLProtocol.requests
        XCTAssertEqual(apiKeyRequests[0].url?.path, "/v1/opportunities/search")
        XCTAssertEqual(apiKeyRequests[0].httpMethod, "POST")
        XCTAssertEqual(apiKeyRequests[0].value(forHTTPHeaderField: "X-API-Key"), "local-dev-api-key")
        let searchBody = try XCTUnwrap(requestBody(apiKeyRequests[0]))
        let searchJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: searchBody) as? [String: Any])
        let pagination = try XCTUnwrap(searchJSON["pagination"] as? [String: Any])
        XCTAssertEqual((pagination["sort_order"] as? [[String: String]])?.first?["order_by"], "relevancy")
        XCTAssertNil(searchJSON["query"])

        try store.save(makeToken(userId: "user-1", issuedAt: Int(Date().timeIntervalSince1970), duration: 30))
        let user = try await dataSource.currentUser()
        let organizations = try await dataSource.organizations()
        let applications = try await dataSource.applications()
        let applicationId = try await dataSource.startApplication(
            competitionId: "comp-1",
            name: "Draft",
            organizationId: nil
        )
        let application = try await dataSource.application(id: "app-1")
        let form = try await dataSource.form(id: "form-1")
        XCTAssertEqual(user.userId, "user-1")
        XCTAssertTrue(organizations.isEmpty)
        XCTAssertTrue(applications.isEmpty)
        XCTAssertEqual(applicationId, "app-1")
        XCTAssertEqual(application.applicationId, "app-1")
        XCTAssertEqual(form.formId, "form-1")
        let saved = try await dataSource.saveForm(
            applicationId: "app-1",
            formId: "form-1",
            response: .object(["answer": .string("yes")])
        )
        XCTAssertEqual(saved.warnings.first?.message, "Check the answer")
        let submission = try await dataSource.submit(applicationId: "app-1")
        let savedIds = try await dataSource.savedOpportunityIds()
        XCTAssertNil(submission.trackingNumber)
        XCTAssertTrue(savedIds.isEmpty)
        try await dataSource.setSaved(true, opportunityId: "opp-1")
        try await dataSource.setSaved(false, opportunityId: "opp-1")

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 14)
        XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, [
            "POST", "GET", "GET", "GET", "POST", "POST", "GET",
            "GET", "PUT", "POST", "POST", "POST", "POST", "DELETE"
        ])
        XCTAssertEqual(requests.map { $0.url?.path ?? "" }, [
            "/v1/opportunities/search",
            "/v1/opportunities/opp-1",
            "/v1/users/user-1",
            "/v1/users/user-1/organizations",
            "/v1/users/user-1/applications",
            "/alpha/applications/start",
            "/alpha/applications/app-1",
            "/alpha/forms/form-1",
            "/alpha/applications/app-1/forms/form-1",
            "/alpha/applications/app-1/submit",
            "/alpha/applications/app-1/submissions",
            "/v1/users/user-1/saved-opportunities/list",
            "/v1/users/user-1/saved-opportunities",
            "/v1/users/user-1/saved-opportunities/opp-1"
        ])
        for request in requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        }
        for request in requests.prefix(2) {
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "local-dev-api-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-SGG-Token"))
        }
        for (index, request) in requests.enumerated() where index >= 2 && index != 7 {
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-SGG-Token"), store.load())
            XCTAssertNil(request.value(forHTTPHeaderField: "X-API-Key"))
        }
        XCTAssertEqual(requests[7].value(forHTTPHeaderField: "X-API-Key"), "local-dev-api-key")
        XCTAssertNil(requests[7].value(forHTTPHeaderField: "X-SGG-Token"))
        XCTAssertEqual(requests[2].url?.path, "/v1/users/user-1")
        XCTAssertEqual(requests[3].url?.path, "/v1/users/user-1/organizations")
        XCTAssertEqual(requests[4].url?.path, "/v1/users/user-1/applications")
        XCTAssertEqual(requests[5].url?.path, "/alpha/applications/start")
        XCTAssertEqual(requests[6].url?.path, "/alpha/applications/app-1")
        XCTAssertEqual(requests[7].url?.path, "/alpha/forms/form-1")
        XCTAssertEqual(requests[8].httpMethod, "PUT")
        XCTAssertEqual(requests[9].url?.path, "/alpha/applications/app-1/submit")
        XCTAssertEqual(requests[10].url?.path, "/alpha/applications/app-1/submissions")
        XCTAssertEqual(requests[11].url?.path, "/v1/users/user-1/saved-opportunities/list")
        XCTAssertEqual(requests[12].httpMethod, "POST")
        XCTAssertEqual(requests[13].httpMethod, "DELETE")
        let applicationListBody = try XCTUnwrap(requestBody(requests[4]))
        let applicationListJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: applicationListBody) as? [String: Any])
        let applicationPagination = try XCTUnwrap(applicationListJSON["pagination"] as? [String: Any])
        XCTAssertEqual((applicationPagination["sort_order"] as? [[String: String]])?.first?["order_by"], "created_at")
        let startBody = try XCTUnwrap(requestBody(requests[5]))
        let startJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: startBody) as? [String: Any])
        XCTAssertEqual(startJSON["competition_id"] as? String, "comp-1")
        XCTAssertEqual(startJSON["application_name"] as? String, "Draft")
        XCTAssertNil(startJSON["organization_id"])
        let saveBody = try XCTUnwrap(requestBody(requests[8]))
        let saveJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: saveBody) as? [String: Any])
        XCTAssertEqual((saveJSON["application_response"] as? [String: String])?["answer"], "yes")
        let savedListBody = try XCTUnwrap(requestBody(requests[11]))
        let savedListJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: savedListBody) as? [String: Any])
        let savedPagination = try XCTUnwrap(savedListJSON["pagination"] as? [String: Any])
        XCTAssertEqual((savedPagination["sort_order"] as? [[String: String]])?.first?["order_by"], "created_at")
        let savedOpportunityBody = try XCTUnwrap(requestBody(requests[12]))
        let savedOpportunityJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: savedOpportunityBody) as? [String: Any]
        )
        XCTAssertEqual(savedOpportunityJSON["opportunity_id"] as? String, "opp-1")
    }

    func testCapturedFormDefinitionFixtureDecodes() throws {
        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(fixture("form-definition.json").utf8)) as? [String: Any]
        )
        XCTAssertEqual(envelope["_captured_http_status"] as? Int, 200)
        let body = try XCTUnwrap(envelope["data"])
        let data = try JSONSerialization.data(withJSONObject: body)
        let form = try JSONDecoder.sg.decode(FormDefinition.self, from: data)
        XCTAssertEqual(form.formId, "1623b310-85be-496a-b84b-34bdee22a68a")
    }

    func testNonLoopbackNeverReceivesAPIKey() async throws {
        let session = makeSession()
        StubURLProtocol.install { _ in (200, #"{"message":"ok"}"#) }
        let token = makeToken(
            userId: "user-1",
            issuedAt: Int(Date().timeIntervalSince1970),
            duration: 30
        )
        let client = APIClient(
            baseURL: URL(string: "https://api.example.org")!,
            apiKey: "local-dev-api-key",
            tokenStore: InMemoryTokenStore(token: token),
            session: session
        )
        _ = try await client.data(path: "/health", authRequirement: .jwtOrAPIKey)
        XCTAssertNil(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "X-API-Key"))
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "X-SGG-Token"), token)
    }

    func testFormFetchUsesLoopbackAPIKeyWhenSignedIn() async throws {
        let session = makeSession()
        let token = makeToken(
            userId: "user-1",
            issuedAt: Int(Date().timeIntervalSince1970),
            duration: 30
        )
        let dataSource = LiveDataSource(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: "local-dev-api-key",
            tokenStore: InMemoryTokenStore(token: token),
            session: session
        )
        StubURLProtocol.install { _ in
            (200, #"{"data":{"form_id":"form-1","form_json_schema":{},"form_ui_schema":[]}}"#)
        }

        let form = try await dataSource.form(id: "form-1")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(form.formId, "form-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "local-dev-api-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-SGG-Token"))
    }

    func testFormFetchDoesNotSendAPIKeyToNonLoopbackHost() async {
        let session = makeSession()
        let token = makeToken(
            userId: "user-1",
            issuedAt: Int(Date().timeIntervalSince1970),
            duration: 30
        )
        let dataSource = LiveDataSource(
            baseURL: URL(string: "https://api.example.org")!,
            apiKey: "local-dev-api-key",
            tokenStore: InMemoryTokenStore(token: token),
            session: session
        )
        StubURLProtocol.install { _ in (200, #"{"data":{}}"#) }

        do {
            _ = try await dataSource.form(id: "form-1")
            XCTFail("Expected unauthorized without a loopback API key")
        } catch {
            XCTAssertEqual(error as? GrantsError, .unauthorized)
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testAPIKeyAuthWithoutAKeyFailsBeforeRequest() async {
        let session = makeSession()
        let token = makeToken(
            userId: "user-1",
            issuedAt: Int(Date().timeIntervalSince1970),
            duration: 30
        )
        StubURLProtocol.install { _ in (200, #"{"data":{}}"#) }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: nil,
            tokenStore: InMemoryTokenStore(token: token),
            session: session
        )

        do {
            _ = try await client.data(path: "/alpha/forms/form-1", authRequirement: .apiKey)
            XCTFail("Expected unauthorized without an API key")
        } catch {
            XCTAssertEqual(error as? GrantsError, .unauthorized)
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testAPIKeyAuthDoesNotRefreshOn401() async {
        let session = makeSession()
        let token = makeToken(
            userId: "user-1",
            issuedAt: Int(Date().timeIntervalSince1970),
            duration: 30
        )
        StubURLProtocol.install { _ in (401, fixture("error-401.json")) }
        let store = InMemoryTokenStore(token: token)
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: "local-dev-api-key",
            tokenStore: store,
            session: session
        )

        do {
            _ = try await client.data(path: "/alpha/forms/form-1", authRequirement: .apiKey)
            XCTFail("Expected unauthorized response")
        } catch {
            XCTAssertEqual(error as? GrantsError, .unauthorized)
        }
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url!.path }, ["/alpha/forms/form-1"])
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "X-API-Key"), "local-dev-api-key")
        XCTAssertNil(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "X-SGG-Token"))
        XCTAssertEqual(store.load(), token)
    }

    func testProactiveRefreshRunsBeforeProtectedRequest() async throws {
        let session = makeSession()
        let issuedAt = 1_700_000_000
        let token = makeToken(userId: "user-1", issuedAt: issuedAt, duration: 30)
        let store = InMemoryTokenStore(token: token)
        let now = Date(timeIntervalSince1970: Double(issuedAt + 1_600))
        StubURLProtocol.install { request in
            request.url?.path == "/v1/users/token/refresh"
                ? (200, #"{"message":"refreshed","data":{}}"#)
                : (200, #"{"message":"ok","data":{}}"#)
        }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: nil,
            tokenStore: store,
            session: session,
            now: { now }
        )

        _ = try await client.data(path: "/resource")

        XCTAssertEqual(StubURLProtocol.requests.map { $0.url!.path }, [
            "/v1/users/token/refresh",
            "/resource"
        ])
    }

    func testProactiveRefreshOfflineKeepsTokenWithoutExpiringSession() async {
        let session = makeSession()
        let issuedAt = 1_700_000_000
        let token = makeToken(userId: "user-1", issuedAt: issuedAt, duration: 30)
        let store = InMemoryTokenStore(token: token)
        let now = Date(timeIntervalSince1970: Double(issuedAt + 1_600))
        StubURLProtocol.install(failingWith: .notConnectedToInternet)
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: nil,
            tokenStore: store,
            session: session,
            now: { now }
        )
        let expired = expectation(forNotification: .sgSessionExpired, object: nil)
        expired.isInverted = true

        do {
            _ = try await client.data(path: "/resource")
            XCTFail("Expected offline refresh error")
        } catch {
            XCTAssertEqual(error as? GrantsError, .offline)
        }
        await fulfillment(of: [expired], timeout: 0.05)
        XCTAssertEqual(store.load(), token)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url!.path }, ["/v1/users/token/refresh"])
    }

    func test401ThenOfflineRefreshKeepsTokenWithoutExpiringSession() async {
        let session = makeSession()
        let token = makeToken(
            userId: "user-1",
            issuedAt: Int(Date().timeIntervalSince1970),
            duration: 30
        )
        let store = InMemoryTokenStore(token: token)
        StubURLProtocol.install(
            handler: { _ in (401, fixture("error-401.json")) },
            failingPaths: ["/v1/users/token/refresh": .notConnectedToInternet]
        )
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: nil,
            tokenStore: store,
            session: session
        )
        let expired = expectation(forNotification: .sgSessionExpired, object: nil)
        expired.isInverted = true

        do {
            _ = try await client.data(path: "/resource")
            XCTFail("Expected offline refresh error")
        } catch {
            XCTAssertEqual(error as? GrantsError, .offline)
        }
        await fulfillment(of: [expired], timeout: 0.05)
        XCTAssertEqual(store.load(), token)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url!.path }, [
            "/resource",
            "/v1/users/token/refresh"
        ])
    }

    func testConcurrentProtectedRequestsShareOneRefresh() async throws {
        let session = makeSession()
        let issuedAt = 1_700_000_000
        let token = makeToken(userId: "user-1", issuedAt: issuedAt, duration: 30)
        let store = InMemoryTokenStore(token: token)
        let now = Date(timeIntervalSince1970: Double(issuedAt + 1_600))
        StubURLProtocol.install { request in
            if request.url?.path == "/v1/users/token/refresh" {
                Thread.sleep(forTimeInterval: 0.05)
                return (200, #"{"message":"refreshed","data":{}}"#)
            }
            return (200, #"{"message":"ok","data":{}}"#)
        }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: nil,
            tokenStore: store,
            session: session,
            now: { now }
        )

        async let first = client.data(path: "/resource/one")
        async let second = client.data(path: "/resource/two")
        _ = try await (first, second)

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.filter { $0.url?.path == "/v1/users/token/refresh" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.path.hasPrefix("/resource/") == true }.count, 2)
    }

    func testRefreshOn401RetriesOnceAndProactiveRefreshes() async throws {
        let session = makeSession()
        let token = makeToken(userId: "user-1", issuedAt: 1_700_000_000, duration: 30)
        let store = InMemoryTokenStore(token: token)
        let now = Date(timeIntervalSince1970: 1_700_001_000)
        StubURLProtocol.install { request in
            if request.url?.path == "/v1/users/token/refresh" {
                return (200, #"{"message":"refreshed","data":{}}"#)
            }
            if StubURLProtocol.requests.filter({ $0.url?.path == "/resource" }).count == 1 {
                return (401, fixture("error-401.json"))
            }
            return (200, #"{"message":"ok","data":{}}"#)
        }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: nil,
            tokenStore: store,
            session: session,
            now: { now }
        )

        _ = try await client.data(path: "/resource")
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.map { $0.url!.path }, [
            "/resource",
            "/v1/users/token/refresh",
            "/resource"
        ])
        XCTAssertEqual(requests[1].httpMethod, "POST")
        XCTAssertNil(requests[1].httpBody)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "X-SGG-Token"), token)
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "X-SGG-Token"), token)
    }

    func testRefreshFailureClearsTokenAndPostsExpiration() async throws {
        let session = makeSession()
        let store = InMemoryTokenStore(token: makeToken(
            userId: "user-1",
            issuedAt: Int(Date().timeIntervalSince1970),
            duration: 30
        ))
        StubURLProtocol.install { request in
            request.url?.path == "/v1/users/token/refresh"
                ? (401, fixture("error-401.json"))
                : (401, fixture("error-401.json"))
        }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: nil,
            tokenStore: store,
            session: session,
            now: { Date() }
        )
        let expired = expectation(forNotification: .sgSessionExpired, object: nil)

        do {
            _ = try await client.data(path: "/resource")
            XCTFail("Expected unauthorized error")
        } catch {
            XCTAssertEqual(error as? GrantsError, .unauthorized)
        }
        await fulfillment(of: [expired], timeout: 1)
        XCTAssertNil(store.load())
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url?.path == "/resource" }.count, 1)
    }

    func testRepeated401AfterRefreshExpiresSession() async throws {
        let session = makeSession()
        let token = makeToken(
            userId: "user-1",
            issuedAt: Int(Date().timeIntervalSince1970),
            duration: 30
        )
        let store = InMemoryTokenStore(token: token)
        StubURLProtocol.install { request in
            request.url?.path == "/v1/users/token/refresh"
                ? (200, #"{"message":"refreshed","data":{}}"#)
                : (401, fixture("error-401.json"))
        }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: nil,
            tokenStore: store,
            session: session
        )
        let expired = expectation(forNotification: .sgSessionExpired, object: nil)

        do {
            _ = try await client.data(path: "/resource")
            XCTFail("Expected unauthorized error")
        } catch {
            XCTAssertEqual(error as? GrantsError, .unauthorized)
        }
        await fulfillment(of: [expired], timeout: 1)
        XCTAssertNil(store.load())
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url!.path }, [
            "/resource",
            "/v1/users/token/refresh",
            "/resource"
        ])
    }

    func testErrorMappingAndMissingUserToken() async throws {
        let session = makeSession()
        StubURLProtocol.install { request in
            switch request.url?.path {
            case "/unauthorized": (401, fixture("error-401.json"))
            case "/forbidden": (403, fixture("error-401.json"))
            case "/missing": (404, fixture("error-404.json"))
            case "/server": (503, #"{"message":"Unavailable","errors":[{"message":"Try later"}]}"#)
            case "/decode": (200, "not-json")
            default: (200, #"{"message":"ok"}"#)
            }
        }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: "local-dev-api-key",
            tokenStore: InMemoryTokenStore(),
            session: session
        )
        do {
            _ = try await client.data(path: "/user", requiresUser: true)
            XCTFail("Expected auth guard")
        } catch {
            XCTAssertEqual(error as? GrantsError, .unauthorized)
        }
        do {
            _ = try await client.data(path: "/unauthorized")
        } catch {
            XCTAssertEqual(error as? GrantsError, .unauthorized)
        }
        do {
            _ = try await client.data(path: "/forbidden")
        } catch {
            XCTAssertEqual(error as? GrantsError, .unauthorized)
        }
        do {
            _ = try await client.data(path: "/missing")
        } catch {
            XCTAssertEqual(error as? GrantsError, .notFound)
        }
        do {
            _ = try await client.data(path: "/server")
        } catch {
            XCTAssertEqual(error as? GrantsError, .server(status: 503, message: "Unavailable Try later"))
        }
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url!.path }, [
            "/unauthorized",
            "/forbidden",
            "/missing",
            "/server"
        ])
    }

    func testNetworkDisconnectionMapsToOffline() async {
        let session = makeSession()
        StubURLProtocol.install(failingWith: .notConnectedToInternet)
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: "local-dev-api-key",
            tokenStore: InMemoryTokenStore(),
            session: session
        )

        do {
            _ = try await client.data(path: "/resource")
            XCTFail("Expected offline error")
        } catch {
            XCTAssertEqual(error as? GrantsError, .offline)
        }
    }

    func testMalformedEndpointResponseMapsToDecodingError() async throws {
        let session = makeSession()
        StubURLProtocol.install { _ in (200, "not-json") }
        let dataSource = LiveDataSource(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: "local-dev-api-key",
            tokenStore: InMemoryTokenStore(),
            session: session
        )

        do {
            _ = try await dataSource.searchOpportunities(SearchRequest())
            XCTFail("Expected a decoding error")
        } catch let error as GrantsError {
            guard case .decoding = error else {
                return XCTFail("Expected decoding error, got \(error)")
            }
        }
    }

    func testDeletingMissingSavedOpportunityIsSuccessful() async throws {
        let session = makeSession()
        let store = InMemoryTokenStore(token: makeToken(
            userId: "user-1",
            issuedAt: Int(Date().timeIntervalSince1970),
            duration: 30
        ))
        StubURLProtocol.install { _ in (404, fixture("error-404.json")) }
        let dataSource = LiveDataSource(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: nil,
            tokenStore: store,
            session: session
        )

        try await dataSource.setSaved(false, opportunityId: "opp-1")

        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertEqual(StubURLProtocol.requests.first?.httpMethod, "DELETE")
    }

    func testSubmit422MapsToServerError() async throws {
        let session = makeSession()
        let token = makeToken(
            userId: "user-1",
            issuedAt: Int(Date().timeIntervalSince1970),
            duration: 30
        )
        StubURLProtocol.install { _ in (422, fixture("application-submit-422.json")) }
        let dataSource = LiveDataSource(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: "local-dev-api-key",
            tokenStore: InMemoryTokenStore(token: token),
            session: session
        )

        do {
            _ = try await dataSource.submit(applicationId: "app-1")
            XCTFail("Expected the API validation error")
        } catch {
            XCTAssertEqual(
                error as? GrantsError,
                .server(
                    status: 422,
                    message: "The application has issues in its form responses. The application form has outstanding errors."
                )
            )
        }
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url!.path }, [
            "/alpha/applications/app-1/submit"
        ])
    }
}

final class LoginGovAuthenticatorTests: XCTestCase {
    func testLegacyInitSharesLiveDataSourceTokenStore() async throws {
        let token = makeToken(
            userId: "user-1",
            issuedAt: Int(Date().timeIntervalSince1970),
            duration: 30
        )
        let session = makeSession()
        StubURLProtocol.install { _ in
            (200, #"{"data":{"user_id":"user-1","email":"demo@example.org","profile":{}}}"#)
        }
        defer { StubURLProtocol.reset() }

        let dataSource = LiveDataSource(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            apiKey: "local-dev-api-key",
            tokenStore: InMemoryTokenStore(),
            session: session
        )
        let authenticator = LoginGovAuthenticator(dataSource: dataSource, testToken: token)

        let profile = await authenticator.restore()

        XCTAssertEqual(profile?.userId, "user-1")
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertEqual(
            StubURLProtocol.requests.first?.value(forHTTPHeaderField: "X-SGG-Token"),
            token
        )
    }

    func testFakeWebAuthenticatorSuccessAndPIVFailure() async throws {
        let profile = UserProfile(userId: "user-1", email: "demo@example.org")
        let dataSource = FakeAuthDataSource(profile: profile)
        let tokenStore = InMemoryTokenStore()
        let callback = try XCTUnwrap(URL(string: "simplergrants://auth/callback?message=success&token=fake"))
        let authenticator = LoginGovAuthenticator(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            dataSource: dataSource,
            tokenStore: tokenStore,
            webAuthenticator: FakeWebAuthenticator(result: .url(callback))
        )
        let signedInProfile = try await authenticator.signIn(pivRequired: false)
        XCTAssertEqual(signedInProfile, profile)
        XCTAssertEqual(tokenStore.load(), "fake")

        let pivCallback = try XCTUnwrap(URL(string: "simplergrants://auth/callback?message=error&login_piv_required_error=required"))
        let pivAuthenticator = LoginGovAuthenticator(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            dataSource: dataSource,
            tokenStore: InMemoryTokenStore(),
            webAuthenticator: FakeWebAuthenticator(result: .url(pivCallback))
        )
        do {
            _ = try await pivAuthenticator.signIn(pivRequired: true)
            XCTFail("Expected PIV error")
        } catch {
            XCTAssertEqual(error as? GrantsError, .server(status: 401, message: "Sign in could not be completed."))
        }
    }

    func testFakeWebAuthenticatorCancellation() async {
        let authenticator = LoginGovAuthenticator(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            dataSource: FakeAuthDataSource(profile: UserProfile(userId: "user", email: "demo@example.org")),
            tokenStore: InMemoryTokenStore(),
            webAuthenticator: FakeWebAuthenticator(result: .cancel)
        )
        do {
            _ = try await authenticator.signIn(pivRequired: false)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected cancellation, got \(error)")
        }
    }

    func testOfflineRestoreUsesCachedProfile() async throws {
        let cacheKey = "sg.cached_user_profile"
        UserDefaults.standard.removeObject(forKey: cacheKey)
        defer { UserDefaults.standard.removeObject(forKey: cacheKey) }

        let profile = UserProfile(userId: "user-1", email: "demo@example.org")
        let tokenStore = InMemoryTokenStore()
        let callback = try XCTUnwrap(URL(string: "simplergrants://auth/callback?message=success&token=fake"))
        let signer = LoginGovAuthenticator(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            dataSource: FakeAuthDataSource(profile: profile),
            tokenStore: tokenStore,
            webAuthenticator: FakeWebAuthenticator(result: .url(callback))
        )
        _ = try await signer.signIn(pivRequired: false)

        let offlineAuthenticator = LoginGovAuthenticator(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            dataSource: FakeAuthDataSource(profile: profile, currentUserError: .offline),
            tokenStore: tokenStore
        )
        let restoredProfile = await offlineAuthenticator.restore()
        XCTAssertEqual(restoredProfile, profile)
    }
}

private final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> (Int, String))?
    private static var failure: URLError.Code?
    private static var failuresByPath: [String: URLError.Code] = [:]
    private static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    static func install(handler: @escaping (URLRequest) -> (Int, String)) {
        lock.lock()
        self.handler = handler
        failure = nil
        failuresByPath = [:]
        recordedRequests = []
        lock.unlock()
    }

    static func install(
        handler: @escaping (URLRequest) -> (Int, String),
        failingPaths: [String: URLError.Code]
    ) {
        lock.lock()
        self.handler = handler
        failure = nil
        failuresByPath = failingPaths
        recordedRequests = []
        lock.unlock()
    }

    static func install(failingWith code: URLError.Code) {
        lock.lock()
        handler = nil
        failure = code
        failuresByPath = [:]
        recordedRequests = []
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        failure = nil
        failuresByPath = [:]
        recordedRequests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        let failure = Self.failure ?? request.url.flatMap { Self.failuresByPath[$0.path] }
        Self.recordedRequests.append(request)
        Self.lock.unlock()

        if let failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        let (status, body) = handler?(request) ?? (500, "stub not installed")
        let data = Data(body.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct FakeWebAuthenticator: WebAuthenticating {
    enum Result {
        case url(URL)
        case cancel
    }

    let result: Result

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        switch result {
        case let .url(url):
            return url
        case .cancel:
            throw CancellationError()
        }
    }
}

private struct FakeAuthDataSource: GrantsDataSource {
    let profile: UserProfile
    let currentUserError: GrantsError?

    init(profile: UserProfile, currentUserError: GrantsError? = nil) {
        self.profile = profile
        self.currentUserError = currentUserError
    }

    func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse { throw GrantsError.offline }
    func opportunity(id: String) async throws -> OpportunityDetail { throw GrantsError.offline }
    func currentUser() async throws -> UserProfile {
        if let currentUserError { throw currentUserError }
        return profile
    }
    func organizations() async throws -> [Organization] { [] }
    func applications() async throws -> [ApplicationSummary] { [] }
    func startApplication(competitionId: String, name: String, organizationId: String?) async throws -> String { "app" }
    func application(id: String) async throws -> Application { throw GrantsError.offline }
    func form(id: String) async throws -> FormDefinition { throw GrantsError.offline }
    func saveForm(applicationId: String, formId: String, response: JSONValue) async throws -> FormSaveResult {
        throw GrantsError.offline
    }
    func submit(applicationId: String) async throws -> SubmissionResult { throw GrantsError.offline }
    func savedOpportunityIds() async throws -> Set<String> { [] }
    func setSaved(_ saved: Bool, opportunityId: String) async throws {}
}

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }
    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        body.append(buffer, count: count)
    }
    return body
}

private func makeToken(userId: String, issuedAt: Int, duration: Int) -> String {
    let payload: [String: Any] = [
        "sub": "token-id",
        "iat": issuedAt,
        "user_id": userId,
        "email": "demo@example.org",
        "session_duration_minutes": duration
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let encoded = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(encoded).signature"
}

private func fixture(_ name: String) -> String {
    let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    return try! String(contentsOf: url, encoding: .utf8)
}
