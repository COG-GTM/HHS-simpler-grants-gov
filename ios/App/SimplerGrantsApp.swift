import SGAsk
import SGCore
import SGDesign
import SGModels
import SGNetworking
import SGSampleData
import SwiftUI

@main
@MainActor
struct SimplerGrantsApp: App {
    @State private var router: AppRouter
    @State private var sessionStore: SessionStore
    @State private var grantsDataSource: any GrantsDataSource
    @State private var askEngine: any AskAnswering
    @State private var draftStore: any DraftStore
    @State private var syncQueue: SyncQueue
    @State private var networkStatus: NetworkStatus

    private let appEnvironment: AppEnvironment
    private let networkMonitor: NWPathNetworkMonitor

    init() {
        SGFonts.registerAll()

        let appEnvironment = AppEnvironment()
        let grantsDataSource: any GrantsDataSource
        let authenticator: any Authenticating
        let networkMonitor = NWPathNetworkMonitor()

        switch appEnvironment.dataMode {
        case .sample:
            let sampleDataSource = SampleDataSource()
            grantsDataSource = sampleDataSource
            authenticator = SampleAuthenticator()
        case let .live(baseURL):
            let token = appEnvironment.uiTestToken
            let tokenStore: any TokenStore
            if let token, !token.isEmpty {
                tokenStore = InMemoryTokenStore(token: token)
            } else {
                tokenStore = KeychainTokenStore()
            }
            let liveDataSource = LiveDataSource(
                baseURL: baseURL,
                apiKey: "local-dev-api-key",
                tokenStore: tokenStore
            )
            grantsDataSource = liveDataSource
            authenticator = LoginGovAuthenticator(
                baseURL: baseURL,
                dataSource: liveDataSource,
                tokenStore: tokenStore,
                testToken: token
            )
        }
        let draftStore = FileDraftStore()
        let syncQueue = SyncQueue(
            dataSource: grantsDataSource,
            draftStore: draftStore,
            monitor: networkMonitor
        )

        self.appEnvironment = appEnvironment
        self.networkMonitor = networkMonitor
        _router = State(initialValue: AppRouter())
        _sessionStore = State(initialValue: SessionStore(authenticator: authenticator))
        _grantsDataSource = State(initialValue: grantsDataSource)
        _askEngine = State(initialValue: AskEngine(dataSource: grantsDataSource))
        _draftStore = State(initialValue: draftStore)
        _syncQueue = State(initialValue: syncQueue)
        _networkStatus = State(initialValue: NetworkStatus())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(sessionStore)
                .environment(\.grantsDataSource, grantsDataSource)
                .environment(\.askEngine, askEngine)
                .environment(\.appEnvironment, appEnvironment)
                .environment(\.draftStore, draftStore)
                .environment(\.syncQueue, syncQueue)
                .environment(\.networkStatus, networkStatus)
                .task {
                    await syncQueue.start()
                    for await isOnline in networkMonitor.updates() {
                        let pendingCount = await syncQueue.pendingCount
                        networkStatus.update(isOnline: isOnline, pendingSyncCount: pendingCount)
                    }
                }
        }
    }
}
