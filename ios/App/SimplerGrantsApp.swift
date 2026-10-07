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

    private let appEnvironment: AppEnvironment

    init() {
        SGFonts.registerAll()

        let appEnvironment = AppEnvironment()
        let grantsDataSource: any GrantsDataSource
        let authenticator: any Authenticating

        switch appEnvironment.dataMode {
        case .sample:
            let sampleDataSource = SampleDataSource()
            grantsDataSource = sampleDataSource
            authenticator = SampleAuthenticator()
        case let .live(baseURL):
            let token = appEnvironment.uiTestToken
            let liveDataSource = LiveDataSource(
                baseURL: baseURL,
                apiKey: token == nil ? "local-dev-api-key" : nil,
                token: token
            )
            grantsDataSource = liveDataSource
            authenticator = LoginGovAuthenticator(
                dataSource: liveDataSource,
                testToken: token
            )
        }

        self.appEnvironment = appEnvironment
        _router = State(initialValue: AppRouter())
        _sessionStore = State(initialValue: SessionStore(authenticator: authenticator))
        _grantsDataSource = State(initialValue: grantsDataSource)
        _askEngine = State(initialValue: AskEngine(dataSource: grantsDataSource))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(sessionStore)
                .environment(\.grantsDataSource, grantsDataSource)
                .environment(\.askEngine, askEngine)
                .environment(\.appEnvironment, appEnvironment)
        }
    }
}
