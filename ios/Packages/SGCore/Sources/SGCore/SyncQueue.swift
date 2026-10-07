import Foundation
import Network
import Observation
import SGModels

public protocol NetworkMonitoring: Sendable {
    var isOnline: Bool { get async }
    func updates() -> AsyncStream<Bool>
}

public final class NWPathNetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ai.cognition.demo.simplergrants.network")
    private let lock = NSLock()
    private var online = true
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.publish(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    public var isOnline: Bool {
        get async {
            lock.withLock { online }
        }
    }

    public func updates() -> AsyncStream<Bool> {
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

    private func publish(_ value: Bool) {
        lock.lock()
        online = value
        let subscribers = Array(continuations.values)
        lock.unlock()
        subscribers.forEach { $0.yield(value) }
    }
}

@Observable
@MainActor
public final class NetworkStatus {
    public private(set) var isOnline: Bool
    public private(set) var pendingSyncCount: Int

    public init(isOnline: Bool = true, pendingSyncCount: Int = 0) {
        self.isOnline = isOnline
        self.pendingSyncCount = pendingSyncCount
    }

    public func update(isOnline: Bool, pendingSyncCount: Int) {
        self.isOnline = isOnline
        self.pendingSyncCount = pendingSyncCount
    }
}

public enum SaveOutcome: Sendable, Equatable {
    case synced(FormSaveResult)
    case queued
    case failed(GrantsError)
}

public actor SyncQueue {
    private let dataSource: any GrantsDataSource
    private let draftStore: any DraftStore
    private let monitor: any NetworkMonitoring
    private let currentOwnerId: @Sendable () async -> String?
    private let requiresOwner: Bool
    private let retryDelays: [Duration]
    private var monitorTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var scheduledRetryId: UUID?
    private var retryAttempt = 0
    private var wasOnline = false
    public private(set) var pendingCount = 0

    public init(
        dataSource: any GrantsDataSource,
        draftStore: any DraftStore,
        monitor: any NetworkMonitoring,
        currentOwnerId: @escaping @Sendable () async -> String? = { nil },
        requiresOwner: Bool = false,
        retryDelays: [Duration] = [.seconds(5), .seconds(15), .seconds(45)]
    ) {
        self.dataSource = dataSource
        self.draftStore = draftStore
        self.monitor = monitor
        self.currentOwnerId = currentOwnerId
        self.requiresOwner = requiresOwner
        self.retryDelays = retryDelays
    }

    public func save(
        applicationId: String,
        formId: String,
        response: JSONValue
    ) async -> SaveOutcome {
        let ownerId = await currentOwnerId()
        do {
            try await draftStore.saveDraft(
                response,
                applicationId: applicationId,
                formId: formId,
                ownerId: ownerId
            )
        } catch {
            return .failed(error as? GrantsError ?? .server(status: 500, message: error.localizedDescription))
        }
        await updatePendingCount()
        guard !requiresOwner || ownerId != nil else { return .queued }

        let result: FormSaveResult
        do {
            result = try await dataSource.saveForm(
                applicationId: applicationId,
                formId: formId,
                response: response
            )
        } catch let error as GrantsError {
            if isRetryable(error) {
                if await shouldScheduleRetry(for: error) {
                    if retryTask == nil {
                        retryAttempt = 0
                    }
                    scheduleRetry()
                }
                return .queued
            }
            try? await draftStore.markFailed(
                applicationId: applicationId,
                formId: formId,
                message: error.localizedDescription,
                failedResponse: response
            )
            await updatePendingCount()
            return .failed(error)
        } catch {
            let mapped = GrantsError.server(status: 500, message: error.localizedDescription)
            try? await draftStore.markFailed(
                applicationId: applicationId,
                formId: formId,
                message: mapped.localizedDescription,
                failedResponse: response
            )
            await updatePendingCount()
            return .failed(mapped)
        }

        try? await draftStore.markSynced(
            applicationId: applicationId,
            formId: formId,
            syncedResponse: response
        )
        await updatePendingCount()
        return .synced(result)
    }

    public func flush() async {
        cancelScheduledRetry()
        guard await monitor.isOnline else {
            await updatePendingCount()
            return
        }
        guard let drafts = try? await draftStore.pendingDrafts() else {
            pendingCount = 0
            return
        }
        let ownerId = await currentOwnerId()
        guard !requiresOwner || ownerId != nil else {
            retryAttempt = 0
            await updatePendingCount()
            return
        }
        var shouldRetry = false

        for draft in drafts where draft.lastError == nil && draft.ownerId == ownerId {
            do {
                _ = try await dataSource.saveForm(
                    applicationId: draft.applicationId,
                    formId: draft.formId,
                    response: draft.response
                )
            } catch let error as GrantsError {
                if await shouldScheduleRetry(for: error) {
                    shouldRetry = true
                } else if !isRetryable(error) {
                    try? await draftStore.markFailed(
                        applicationId: draft.applicationId,
                        formId: draft.formId,
                        message: error.localizedDescription,
                        failedResponse: draft.response
                    )
                }
                continue
            } catch {
                try? await draftStore.markFailed(
                    applicationId: draft.applicationId,
                    formId: draft.formId,
                    message: error.localizedDescription,
                    failedResponse: draft.response
                )
                continue
            }
            try? await draftStore.markSynced(
                applicationId: draft.applicationId,
                formId: draft.formId,
                syncedResponse: draft.response
            )
        }
        if shouldRetry {
            scheduleRetry()
        } else {
            retryAttempt = 0
        }
        await updatePendingCount()
    }

    public func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self, monitor] in
            for await online in monitor.updates() {
                await self?.networkChanged(online)
            }
        }
    }

    private func networkChanged(_ online: Bool) async {
        let transitionedOnline = online && !wasOnline
        wasOnline = online
        if transitionedOnline {
            await flush()
        } else {
            if !online {
                cancelScheduledRetry()
            }
            await updatePendingCount()
        }
    }

    private func shouldScheduleRetry(for error: GrantsError) async -> Bool {
        switch error {
        case .offline:
            return await monitor.isOnline
        case let .server(status, _) where (500..<600).contains(status):
            return await monitor.isOnline
        default:
            return false
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil, retryDelays.indices.contains(retryAttempt) else { return }
        let delay = retryDelays[retryAttempt]
        let identifier = UUID()
        retryAttempt += 1
        scheduledRetryId = identifier
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.runScheduledRetry(identifier: identifier)
        }
    }

    private func runScheduledRetry(identifier: UUID) async {
        guard scheduledRetryId == identifier else { return }
        retryTask = nil
        scheduledRetryId = nil
        await flush()
    }

    private func cancelScheduledRetry() {
        retryTask?.cancel()
        retryTask = nil
        scheduledRetryId = nil
    }

    private func updatePendingCount() async {
        pendingCount = (try? await draftStore.pendingDrafts().count) ?? 0
    }

    private func isRetryable(_ error: GrantsError) -> Bool {
        switch error {
        case .offline, .unauthorized:
            return true
        case let .server(status, _):
            return (500..<600).contains(status)
        case .notFound, .decoding:
            return false
        }
    }
}
