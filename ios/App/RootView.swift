import SGCore
import SGDesign
import SGFeatureApply
import SGFeatureAsk
import SGFeatureOnboarding
import SGFeatureProfile
import SGFeatureSearch
import SGSampleData
import SwiftUI
import UIKit

struct RootView: View {
    @AppStorage("sg.onboarding.completed") private var hasCompletedOnboarding = false
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.grantsDataSource) private var grantsDataSource
    @Environment(\.draftStore) private var draftStore
    @Environment(\.syncQueue) private var syncQueue
    @Environment(\.networkStatus) private var networkStatus
    @State private var isRestoring = true
    @State private var didApplyInitialDeepLink = false
#if DEBUG
    @State private var didAttemptAutoSignIn = false
    @State private var didResetPersistedState = false
#endif

    private var shouldSkipOnboarding: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let index = arguments.firstIndex(of: "-SGSkipOnboarding"),
            arguments.indices.contains(index + 1)
        else {
            return false
        }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }

#if DEBUG
    private var shouldResetPersistedState: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let index = arguments.firstIndex(of: "-SGResetState"),
            arguments.indices.contains(index + 1)
        else {
            return false
        }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }

    private var shouldAutoSignIn: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let index = arguments.firstIndex(of: "-SGAutoSignIn"),
            arguments.indices.contains(index + 1)
        else {
            return false
        }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }

    private var shouldPrefillApplicationForUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("-SGUITestPrefillApplication")
    }
#endif

    var body: some View {
        Group {
            if isRestoring {
                Color(uiColor: UIColor(red: 246 / 255, green: 246 / 255, blue: 243 / 255, alpha: 1))
                    .ignoresSafeArea()
            } else {
                if hasCompletedOnboarding || shouldSkipOnboarding || isSignedIn {
                    MainTabsView()
                } else {
                    OnboardingFlowView(onFinish: finishOnboarding)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !isRestoring, let networkStatus, !networkStatus.isOnline {
                InlineErrorBanner(
                    message: "shell.offline.message".localized(bundle: .main),
                    retry: { Task { await flushSyncQueue() } }
                )
                .accessibilityIdentifier("shell.offline.banner")
            }
        }
        .task {
#if DEBUG
            if shouldResetPersistedState, !didResetPersistedState {
                didResetPersistedState = true
                let defaults = UserDefaults.standard
                [
                    "sg.onboarding.completed",
                    "sg.ask.eligibility",
                    "sg.ask.recentQuestions",
                    "sg.search.recents",
                    "sg.roadmap.votes"
                ].forEach(defaults.removeObject(forKey:))
                defaults.dictionaryRepresentation().keys
                    .filter { $0.hasPrefix("sg.apply.progress.") }
                    .forEach(defaults.removeObject(forKey:))
                try? await draftStore.removeAll()
            }
            if shouldPrefillApplicationForUITest,
               case .sample = appEnvironment.dataMode,
               let sampleDataSource = grantsDataSource as? SampleDataSource {
                do {
                    try await sampleDataSource.prefillApplicationForUITest()
                } catch {
                    assertionFailure("Failed to prefill sample application for UI test: \(error)")
                }
            }
#endif
            await sessionStore.restore()
#if DEBUG
            if shouldAutoSignIn, !didAttemptAutoSignIn {
                if case .signedOut = sessionStore.state {
                    didAttemptAutoSignIn = true
                    hasCompletedOnboarding = true
                    await sessionStore.signIn(pivRequired: false)
                }
            }
#endif
            isRestoring = false
            applyInitialDeepLinkIfNeeded()
        }
        .onOpenURL { router.open($0) }
        .onChange(of: sessionStore.state) { oldState, newState in
            if case .signedIn = newState {
                hasCompletedOnboarding = true
                Task { await flushSyncQueue() }
            }
            if case .signedIn = oldState, case .signedOut = newState {
                router.reset()
            }
        }
    }

    @MainActor
    private func flushSyncQueue() async {
        await syncQueue.flush()
        let pendingCount = await syncQueue.pendingCount
        networkStatus?.update(
            isOnline: networkStatus?.isOnline ?? true,
            pendingSyncCount: pendingCount
        )
    }

    private var isSignedIn: Bool {
        if case .signedIn = sessionStore.state { return true }
        return false
    }

    private func applyInitialDeepLinkIfNeeded() {
        guard !didApplyInitialDeepLink else { return }
        didApplyInitialDeepLink = true
        if let deepLink = appEnvironment.deepLink {
            router.open(deepLink)
        }
    }

    private func finishOnboarding(_ result: OnboardingResult) {
        hasCompletedOnboarding = true
        switch result {
        case .signedIn:
            break
        case .guest:
            sessionStore.continueAsGuest()
        }
        router.select(.ask)
    }
}

private struct MainTabsView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        TabView(selection: Binding(
            get: { router.tab },
            set: { router.select($0) }
        )) {
            tabStack(.ask)
                .tabItem {
                    Label("tabs.ask".localized(bundle: .main), systemImage: "bubble.left")
                        .accessibilityHidden(true)
                }
                .tag(AppTab.ask)

            tabStack(.search)
                .tabItem {
                    Label("tabs.search".localized(bundle: .main), systemImage: "magnifyingglass")
                        .accessibilityHidden(true)
                }
                .tag(AppTab.search)

            tabStack(.apply)
                .tabItem {
                    Label("tabs.apply".localized(bundle: .main), systemImage: "doc.text")
                        .accessibilityHidden(true)
                }
                .tag(AppTab.apply)

            tabStack(.profile)
                .tabItem {
                    Label("tabs.profile".localized(bundle: .main), systemImage: "person.circle")
                        .accessibilityHidden(true)
                }
                .tag(AppTab.profile)
        }
        .background(canvasBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowTabBar {
                SGTabBar()
            }
        }
    }

    private func tabStack(_ tab: AppTab) -> some View {
        NavigationStack(path: router.routesBinding(for: tab)) {
            tabRoot(tab)
                .background(canvasBackground.ignoresSafeArea())
                .navigationDestination(for: AppRoute.self) { route in
                    RouteView(route: route)
                }
        }
        .background(canvasBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        switch tab {
        case .ask:
            AskHomeView()
        case .search:
            SearchHomeView()
        case .apply:
            ApplyHomeView()
        case .profile:
            ProfileView()
        }
    }

    private var shouldShowTabBar: Bool {
        guard let route = router.routes(for: router.tab).last else { return true }
        switch route {
        case .answer(_), .opportunity(_), .form(_, _), .review(_), .submitted(_, _), .roadmap:
            return false
        case .results(_), .application(_):
            return true
        }
    }

    private var canvasBackground: Color {
        Color(uiColor: UIColor(red: 246 / 255, green: 246 / 255, blue: 243 / 255, alpha: 1))
    }
}
