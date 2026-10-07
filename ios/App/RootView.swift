import SGCore
import SGDesign
import SGFeatureApply
import SGFeatureAsk
import SGFeatureOnboarding
import SGFeatureProfile
import SGFeatureSearch
import SwiftUI

struct RootView: View {
    @AppStorage("sg.onboarding.completed") private var hasCompletedOnboarding = false
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var sessionStore

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
            if hasCompletedOnboarding || shouldSkipOnboarding {
                MainTabsView()
            } else {
                OnboardingFlowView(onFinish: finishOnboarding)
            }
        }
        .task {
            await sessionStore.restore()
        }
    }

    private func finishOnboarding(_ result: OnboardingResult) {
        hasCompletedOnboarding = true
        switch result {
        case .signedIn:
            Task {
                await sessionStore.signIn(pivRequired: false)
            }
        case .guest:
            sessionStore.continueAsGuest()
        }
        router.tab = .ask
    }
}

private struct MainTabsView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        TabView(selection: Binding(
            get: { router.tab },
            set: { router.tab = $0 }
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
        .tint(Color(red: 31 / 255, green: 61 / 255, blue: 110 / 255))
        .toolbarBackground(Color(red: 250 / 255, green: 250 / 255, blue: 248 / 255), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private func tabStack(_ tab: AppTab) -> some View {
        NavigationStack(path: router.binding(for: tab)) {
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
}
