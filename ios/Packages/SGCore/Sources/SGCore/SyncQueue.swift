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
    private var monitorTask: Task<Void, Never>?
    private var wasOnline = false
    public private(set) var pendingCount = 0

    public init(
        dataSource: any GrantsDataSource,
        draftStore: any DraftStore,
        monitor: any NetworkMonitoring
    ) {
        self.dataSource = dataSource
        self.draftStore = draftStore
        self.monitor = monitor
    }

    public func save(
        applicationId: String,
        formId: String,
        response: JSONValue
    ) async -> SaveOutcome {
        do {
            try await draftStore.saveDraft(response, applicationId: applicationId, formId: formId)
        } catch {
            return .failed(error as? GrantsError ?? .server(status: 500, message: error.localizedDescription))
        }
        await updatePendingCount()

        do {
            let result = try await dataSource.saveForm(
                applicationId: applicationId,
                formId: formId,
                response: response
            )
            try await draftStore.markSynced(
                applicationId: applicationId,
                formId: formId,
                syncedResponse: response
            )
            await updatePendingCount()
            return .synced(result)
        } catch let error as GrantsError {
            if isRetryable(error) {
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
    }

    public func flush() async {
        guard await monitor.isOnline else {
            await updatePendingCount()
            return
        }
        guard let drafts = try? await draftStore.pendingDrafts() else {
            pendingCount = 0
            return
        }

        for draft in drafts where draft.lastError == nil {
            do {
                _ = try await dataSource.saveForm(
                    applicationId: draft.applicationId,
                    formId: draft.formId,
                    response: draft.response
                )
                try await draftStore.markSynced(
                    applicationId: draft.applicationId,
                    formId: draft.formId,
                    syncedResponse: draft.response
                )
            } catch let error as GrantsError {
                if !isRetryable(error) {
                    try? await draftStore.markFailed(
                        applicationId: draft.applicationId,
                        formId: draft.formId,
                        message: error.localizedDescription,
                        failedResponse: draft.response
                    )
                }
            } catch {
                try? await draftStore.markFailed(
                    applicationId: draft.applicationId,
                    formId: draft.formId,
                    message: error.localizedDescription,
                    failedResponse: draft.response
                )
            }
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
            await updatePendingCount()
        }
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
