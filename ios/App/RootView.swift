import SGCore
import SGDesign
import SGFeatureApply
import SGFeatureAsk
import SGFeatureOnboarding
import SGFeatureProfile
import SGFeatureSearch
import SwiftUI
import UIKit

struct RootView: View {
    @AppStorage("sg.onboarding.completed") private var hasCompletedOnboarding = false
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.syncQueue) private var syncQueue
    @Environment(\.networkStatus) private var networkStatus
    @State private var isRestoring = true
    @State private var didApplyInitialDeepLink = false

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
            await sessionStore.restore()
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
            Task { await sessionStore.signIn(pivRequired: false) }
        case .guest:
            sessionStore.continueAsGuest()
        }
        router.select(.ask)
    }
}

private struct MainTabsView: View {
    @Environment(AppRouter.self) private var router

    private static let appearanceConfigured: Void = {
        configureTabBarAppearance()
    }()

    var body: some View {
        let _ = Self.appearanceConfigured
        return TabView(selection: Binding(
            get: { router.tab },
            set: { router.select($0) }
        )) {
            tabStack(.ask)
                .tabItem {
                    Label("tabs.ask".localized(bundle: .main), systemImage: "bubble.left")
                }
                .tag(AppTab.ask)

            tabStack(.search)
                .tabItem {
                    Label("tabs.search".localized(bundle: .main), systemImage: "magnifyingglass")
                }
                .tag(AppTab.search)

            tabStack(.apply)
                .tabItem {
                    Label("tabs.apply".localized(bundle: .main), systemImage: "doc.text")
                }
                .tag(AppTab.apply)

            tabStack(.profile)
                .tabItem {
                    Label("tabs.profile".localized(bundle: .main), systemImage: "person.circle")
                }
                .tag(AppTab.profile)
        }
        .tint(Color(uiColor: UIColor(red: 31 / 255, green: 61 / 255, blue: 110 / 255, alpha: 1)))
        .toolbarBackground(Color(uiColor: UIColor(red: 250 / 255, green: 250 / 255, blue: 248 / 255, alpha: 0.94)), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private func tabStack(_ tab: AppTab) -> some View {
        NavigationStack(path: router.routesBinding(for: tab)) {
            tabRoot(tab)
                .navigationDestination(for: AppRoute.self) { route in
                    RouteView(route: route)
                }
        }
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

    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(
            red: 250 / 255,
            green: 250 / 255,
            blue: 248 / 255,
            alpha: 0.94
        )
        appearance.shadowColor = UIColor(red: 228 / 255, green: 228 / 255, blue: 223 / 255, alpha: 1)
        let selected = UIColor(red: 31 / 255, green: 61 / 255, blue: 110 / 255, alpha: 1)
        let unselected = UIColor(red: 138 / 255, green: 143 / 255, blue: 153 / 255, alpha: 1)
        let font = UIFont(name: "PublicSans-Medium", size: 10) ?? .systemFont(ofSize: 10, weight: .medium)
        for itemAppearance in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            itemAppearance.normal.iconColor = unselected
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: unselected, .font: font]
            itemAppearance.selected.iconColor = selected
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: selected, .font: font]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
