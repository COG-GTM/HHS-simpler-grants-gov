import SGModels
import SwiftUI

private struct DraftStoreKey: EnvironmentKey {
    static let defaultValue: any DraftStore = FileDraftStore(
        directoryURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("SimplerGrantsPreviewDrafts", isDirectory: true)
    )
}

private struct SyncQueueKey: EnvironmentKey {
    static let defaultValue: SyncQueue = SyncQueue(
        dataSource: PreviewDataSource(),
        draftStore: DraftStoreKey.defaultValue,
        monitor: NWPathNetworkMonitor()
    )
}

private struct NetworkStatusKey: EnvironmentKey {
    static let defaultValue: NetworkStatus? = nil
}

public extension EnvironmentValues {
    var draftStore: any DraftStore {
        get { self[DraftStoreKey.self] }
        set { self[DraftStoreKey.self] = newValue }
    }

    var syncQueue: SyncQueue {
        get { self[SyncQueueKey.self] }
        set { self[SyncQueueKey.self] = newValue }
    }

    var networkStatus: NetworkStatus? {
        get { self[NetworkStatusKey.self] }
        set { self[NetworkStatusKey.self] = newValue }
    }
}
