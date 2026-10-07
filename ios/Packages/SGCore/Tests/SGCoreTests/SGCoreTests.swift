import Foundation
import SGCore
import SGModels
import SwiftUI
import XCTest

final class DraftStoreTests: XCTestCase {
    func testDraftPersistsAcrossStoresAndCanBeMarkedSynced() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = FileDraftStore(directoryURL: directory)
        let value: JSONValue = .object(["answer": .string("saved")])

        try await first.saveDraft(value, applicationId: "app-1", formId: "form-1")

        let second = FileDraftStore(directoryURL: directory)
        let loaded = try await second.loadDraft(applicationId: "app-1", formId: "form-1")
        let pendingBeforeSync = try await second.pendingDrafts()
        XCTAssertEqual(loaded, value)
        XCTAssertEqual(pendingBeforeSync.count, 1)
        try await second.markSynced(applicationId: "app-1", formId: "form-1")
        let pendingAfterSync = try await second.pendingDrafts()
        let retained = try await second.loadDraft(applicationId: "app-1", formId: "form-1")
        XCTAssertTrue(pendingAfterSync.isEmpty)
        XCTAssertEqual(retained, value)
    }

    func testLegacyRawJSONDraftLoadsAsPending() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let applicationId = "legacy-app"
        let formId = "legacy-form"
        let value: JSONValue = .object(["legacy": .bool(true)])
        let fileName = Data("\(applicationId)\u{0}\(formId)".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        try JSONEncoder.sg.encode(value).write(
            to: directory.appendingPathComponent("\(fileName).json")
        )

        let store = FileDraftStore(directoryURL: directory)
        let loaded = try await store.loadDraft(applicationId: applicationId, formId: formId)
        XCTAssertEqual(loaded, value)
        let pending = try await store.pendingDrafts()
        XCTAssertEqual(pending.map(\.applicationId), [applicationId])
        XCTAssertEqual(pending.first?.formId, formId)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

final class SyncQueueTests: XCTestCase {
    func testOfflineSaveQueuesAndFlushKeepsSyncedDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dataSource = FakeDataSource()
        await dataSource.setSaveError(.offline)
        let monitor = FakeNetworkMonitor(isOnline: false)
        let drafts = FileDraftStore(directoryURL: directory)
        let queue = SyncQueue(dataSource: dataSource, draftStore: drafts, monitor: monitor)
        await queue.start()

        let response: JSONValue = .object(["name": .string("draft")])
        let outcome = await queue.save(applicationId: "app", formId: "form", response: response)
        XCTAssertEqual(outcome, .queued)
        let pendingBeforeFlush = await queue.pendingCount
        XCTAssertEqual(pendingBeforeFlush, 1)

        await dataSource.setSaveError(nil)
        monitor.setOnline(true)
        for _ in 0..<30 {
            if await queue.pendingCount == 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        let pendingAfterFlush = await queue.pendingCount
        let retained = try await drafts.loadDraft(applicationId: "app", formId: "form")
        let draftsAfterFlush = try await drafts.pendingDrafts()
        let saveCount = await dataSource.saveCount
        XCTAssertEqual(pendingAfterFlush, 0)
        XCTAssertEqual(retained, response)
        XCTAssertTrue(draftsAfterFlush.isEmpty)
        XCTAssertEqual(saveCount, 2)
    }

    func testNonRetryableFailureIsRecordedAndNotRetried() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dataSource = FakeDataSource()
        await dataSource.setSaveError(.notFound)
        let monitor = FakeNetworkMonitor(isOnline: true)
        let drafts = FileDraftStore(directoryURL: directory)
        let queue = SyncQueue(dataSource: dataSource, draftStore: drafts, monitor: monitor)

        guard case .failed(.notFound) = await queue.save(
            applicationId: "app",
            formId: "form",
            response: .object([:])
        ) else {
            return XCTFail("Expected a non-retryable failure")
        }
        await queue.flush()

        let saveCount = await dataSource.saveCount
        XCTAssertEqual(saveCount, 1)
        let pending = try await drafts.pendingDrafts()
        XCTAssertEqual(pending.count, 1)
        XCTAssertNotNil(pending.first?.lastError)
        let retained = try await drafts.loadDraft(applicationId: "app", formId: "form")
        XCTAssertEqual(retained, .object([:]))
    }

    func testSaveDoesNotMarkNewerDraftSyncedAfterOlderSaveSucceeds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = FileDraftStore(directoryURL: directory)
        let dataSource = FakeDataSource()
        let monitor = FakeNetworkMonitor(isOnline: true)
        let queue = SyncQueue(dataSource: dataSource, draftStore: drafts, monitor: monitor)
        let oldResponse: JSONValue = .object(["answer": .string("v1")])
        let newResponse: JSONValue = .object(["answer": .string("v2")])
        await dataSource.writeNewDraftDuringNextSave(newResponse, draftStore: drafts)

        let outcome = await queue.save(
            applicationId: "app",
            formId: "form",
            response: oldResponse
        )

        guard case .synced = outcome else {
            return XCTFail("Expected the original response to sync")
        }
        let pending = try await drafts.pendingDrafts()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.response, newResponse)
        XCTAssertTrue(pending.first?.needsSync == true)
        XCTAssertNil(pending.first?.lastError)
    }

    func testSaveFailureDoesNotMarkNewerDraftFailed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = FileDraftStore(directoryURL: directory)
        let dataSource = FakeDataSource()
        await dataSource.setSaveError(.notFound)
        let monitor = FakeNetworkMonitor(isOnline: true)
        let queue = SyncQueue(dataSource: dataSource, draftStore: drafts, monitor: monitor)
        let oldResponse: JSONValue = .object(["answer": .string("v1")])
        let newResponse: JSONValue = .object(["answer": .string("v2")])
        await dataSource.writeNewDraftDuringNextSave(newResponse, draftStore: drafts)

        let outcome = await queue.save(
            applicationId: "app",
            formId: "form",
            response: oldResponse
        )

        XCTAssertEqual(outcome, .failed(.notFound))
        let pending = try await drafts.pendingDrafts()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.response, newResponse)
        XCTAssertTrue(pending.first?.needsSync == true)
        XCTAssertNil(pending.first?.lastError)
    }

    func testFlushDoesNotMarkNewerDraftSyncedAfterOlderSaveSucceeds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = FileDraftStore(directoryURL: directory)
        let dataSource = FakeDataSource()
        await dataSource.setSaveError(.offline)
        let monitor = FakeNetworkMonitor(isOnline: true)
        let queue = SyncQueue(dataSource: dataSource, draftStore: drafts, monitor: monitor)
        let oldResponse: JSONValue = .object(["answer": .string("v1")])
        let newResponse: JSONValue = .object(["answer": .string("v2")])
        _ = await queue.save(applicationId: "app", formId: "form", response: oldResponse)
        await dataSource.setSaveError(nil)
        await dataSource.writeNewDraftDuringNextSave(newResponse, draftStore: drafts)

        await queue.flush()

        let pending = try await drafts.pendingDrafts()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.response, newResponse)
        XCTAssertTrue(pending.first?.needsSync == true)
        XCTAssertNil(pending.first?.lastError)
    }
}

@MainActor
final class AppRouterTests: XCTestCase {
    func testDeepLinksAndNavigationRules() throws {
        let opportunity = try XCTUnwrap(URL(string: "simplergrants://opportunity/abc-123"))
        XCTAssertEqual(DeepLink.parse(opportunity), .opportunity(id: "abc-123"))
        XCTAssertNil(DeepLink.parse(try XCTUnwrap(URL(string: "simplergrants://auth/callback?message=success"))))
        XCTAssertNil(DeepLink.parse(try XCTUnwrap(URL(string: "simplergrants://opportunity"))))
        XCTAssertEqual(
            DeepLink.parse(try XCTUnwrap(URL(string: "https://simpler.grants.gov/opportunity/456"))),
            .opportunity(id: "456")
        )

        let router = AppRouter()
        XCTAssertTrue(router.open(opportunity))
        XCTAssertEqual(router.tab, .search)
        XCTAssertEqual(router.routes(for: .search), [.opportunity(id: "abc-123")])
        router.push(.opportunity(id: "abc-123"))
        XCTAssertEqual(router.routes(for: .search).count, 1)
        router.push(.results(SearchRequest()))
        router.select(.search)
        XCTAssertTrue(router.routes(for: .search).isEmpty)
        XCTAssertFalse(router.open(try XCTUnwrap(URL(string: "simplergrants://auth/callback"))))
    }

    func testNavigationPathSetterTruncatesAndIgnoresGrowth() {
        let router = AppRouter()
        router.push(.answer(question: "q"))
        router.push(.results(SearchRequest()))
        router.setNavigationPath(NavigationPath([AppRoute.answer(question: "q")]), for: .ask)
        XCTAssertEqual(router.routes(for: .ask), [.answer(question: "q")])
        router.setNavigationPath(
            NavigationPath([
                AppRoute.roadmap,
                AppRoute.application(id: "app-1")
            ]),
            for: .ask
        )
        XCTAssertEqual(router.routes(for: .ask), [.answer(question: "q")])
        let routesBinding = router.routesBinding(for: .ask)
        routesBinding.wrappedValue = [.roadmap, .application(id: "app-1")]
        XCTAssertEqual(router.routes(for: .ask), [.answer(question: "q")])
        routesBinding.wrappedValue = []
        XCTAssertTrue(router.routes(for: .ask).isEmpty)
        router.reset()
        XCTAssertEqual(router.tab, .ask)
        XCTAssertTrue(router.routes(for: .ask).isEmpty)
    }
}

@MainActor
final class SessionStoreTests: XCTestCase {
    func testCancellationPreservesStateAndLeavesNoError() async {
        let authenticator = FakeAuthenticator(signInResult: .cancel)
        let store = SessionStore(authenticator: authenticator)
        store.continueAsGuest()

        await store.signIn(pivRequired: false)

        XCTAssertEqual(store.state, .guest)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isBusy)
    }

    func testSignInErrorBusyGuardAndExpiration() async throws {
        let authenticator = FakeAuthenticator(
            signInResult: .error(.server(status: 503, message: "unavailable")),
            signInDelay: .milliseconds(80)
        )
        let store = SessionStore(authenticator: authenticator)
        let signIn = Task { await store.signIn(pivRequired: false) }
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(store.isBusy)
        await store.signIn(pivRequired: false)
        await signIn.value

        let signInCount = await authenticator.signInCount
        XCTAssertEqual(signInCount, 1)
        XCTAssertEqual(store.lastError, .server(status: 503, message: "unavailable"))
        store.handleSessionExpired()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(store.lastError, .unauthorized)
    }

    func testRestoreDoesNotReplaceGuestState() async throws {
        let authenticator = FakeAuthenticator(
            signInResult: .cancel,
            restoreResult: nil,
            restoreDelay: .milliseconds(60)
        )
        let store = SessionStore(authenticator: authenticator)
        let restore = Task { await store.restore() }
        try await Task.sleep(for: .milliseconds(10))
        store.continueAsGuest()
        await restore.value
        XCTAssertEqual(store.state, .guest)
    }
}

final class AppEnvironmentTests: XCTestCase {
    func testSettingsDefaultAndLaunchArguments() throws {
        let suiteName = "AppEnvironmentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppEnvironment(arguments: [], userDefaults: defaults).dataMode, .sample)
        defaults.set("live", forKey: "sg_data_mode")
        XCTAssertEqual(
            AppEnvironment(arguments: [], userDefaults: defaults).dataMode,
            .live(baseURL: URL(string: "http://127.0.0.1:8080")!)
        )
        XCTAssertEqual(
            AppEnvironment(arguments: ["-SGDataMode", "sample"], userDefaults: defaults).dataMode,
            .sample
        )

        let deepLink = try XCTUnwrap(URL(string: "simplergrants://opportunity/123"))
        XCTAssertEqual(
            AppEnvironment(arguments: ["-SGDeepLink", deepLink.absoluteString]).deepLink,
            deepLink
        )
    }
}

private actor FakeAuthenticator: Authenticating {
    enum Result {
        case cancel
        case error(GrantsError)
        case user(UserProfile)
    }

    private let signInResult: Result
    private let restoreResult: UserProfile?
    private let signInDelay: Duration
    private let restoreDelay: Duration
    private(set) var signInCount = 0

    init(
        signInResult: Result,
        restoreResult: UserProfile? = nil,
        signInDelay: Duration = .zero,
        restoreDelay: Duration = .zero
    ) {
        self.signInResult = signInResult
        self.restoreResult = restoreResult
        self.signInDelay = signInDelay
        self.restoreDelay = restoreDelay
    }

    func signIn(pivRequired: Bool) async throws -> UserProfile {
        signInCount += 1
        try await Task.sleep(for: signInDelay)
        switch signInResult {
        case .cancel:
            throw CancellationError()
        case let .error(error):
            throw error
        case let .user(user):
            return user
        }
    }

    func restore() async -> UserProfile? {
        try? await Task.sleep(for: restoreDelay)
        return restoreResult
    }

    func signOut() async {}
}

private actor FakeDataSource: GrantsDataSource {
    private var saveError: GrantsError?
    private(set) var saveCount = 0
    private var draftWriteDuringSave: (store: any DraftStore, response: JSONValue)?

    func setSaveError(_ error: GrantsError?) {
        saveError = error
    }

    func writeNewDraftDuringNextSave(_ response: JSONValue, draftStore: any DraftStore) {
        draftWriteDuringSave = (draftStore, response)
    }

    func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse { throw GrantsError.offline }
    func opportunity(id: String) async throws -> OpportunityDetail { throw GrantsError.offline }
    func currentUser() async throws -> UserProfile { throw GrantsError.offline }
    func organizations() async throws -> [Organization] { throw GrantsError.offline }
    func applications() async throws -> [ApplicationSummary] { throw GrantsError.offline }
    func startApplication(competitionId: String, name: String, organizationId: String?) async throws -> String { throw GrantsError.offline }
    func application(id: String) async throws -> Application { throw GrantsError.offline }
    func form(id: String) async throws -> FormDefinition { throw GrantsError.offline }
    func submit(applicationId: String) async throws -> SubmissionResult { throw GrantsError.offline }
    func savedOpportunityIds() async throws -> Set<String> { throw GrantsError.offline }
    func setSaved(_ saved: Bool, opportunityId: String) async throws { throw GrantsError.offline }

    func saveForm(applicationId: String, formId: String, response: JSONValue) async throws -> FormSaveResult {
        saveCount += 1
        let saveError = self.saveError
        let draftWrite = draftWriteDuringSave
        draftWriteDuringSave = nil
        if let draftWrite {
            try await draftWrite.store.saveDraft(
                draftWrite.response,
                applicationId: applicationId,
                formId: formId
            )
        }
        if let saveError { throw saveError }
        return FormSaveResult(
            form: ApplicationForm(
                applicationFormId: "record",
                formId: formId,
                form: FormDefinition(formId: formId),
                applicationResponse: response,
                isRequired: true
            )
        )
    }
}

private final class FakeNetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var online: Bool
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init(isOnline: Bool) {
        online = isOnline
    }

    var isOnline: Bool {
        get async {
            lock.withLock { online }
        }
    }

    func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let identifier = UUID()
            lock.lock()
            continuations[identifier] = continuation
            let currentValue = online
            lock.unlock()
            continuation.yield(currentValue)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: identifier)
                self.lock.unlock()
            }
        }
    }

    func setOnline(_ value: Bool) {
        lock.lock()
        online = value
        let subscribers = Array(continuations.values)
        lock.unlock()
        subscribers.forEach { $0.yield(value) }
    }
}
