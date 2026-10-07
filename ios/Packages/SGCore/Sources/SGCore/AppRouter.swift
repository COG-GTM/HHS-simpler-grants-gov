import Observation
import SGModels
import SwiftUI

public enum AppTab: Hashable, Sendable, CaseIterable, Identifiable {
    case ask
    case search
    case apply
    case profile

    public var id: Self { self }
}

public enum AppRoute: Hashable, Sendable {
    case answer(question: String)
    case results(SearchRequest)
    case opportunity(id: String)
    case application(id: String)
    case form(applicationId: String, formId: String)
    case review(applicationId: String)
    case submitted(applicationId: String, trackingNumber: String?)
    case roadmap
}

@Observable
@MainActor
public final class AppRouter {
    public var tab: AppTab
    private var paths: [AppTab: NavigationPath]

    public init(tab: AppTab = .ask) {
        self.tab = tab
        paths = Dictionary(
            uniqueKeysWithValues: AppTab.allCases.map { ($0, NavigationPath()) }
        )
    }

    public func push(_ route: AppRoute, in tab: AppTab? = nil) {
        let tab = tab ?? self.tab
        var path = paths[tab] ?? NavigationPath()
        path.append(route)
        paths[tab] = path
    }

    public func popToRoot(_ tab: AppTab) {
        paths[tab] = NavigationPath()
    }

    public func navigationPath(for tab: AppTab) -> NavigationPath {
        paths[tab] ?? NavigationPath()
    }

    public func setNavigationPath(_ path: NavigationPath, for tab: AppTab) {
        paths[tab] = path
    }

    public func binding(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { self.navigationPath(for: tab) },
            set: { self.setNavigationPath($0, for: tab) }
        )
    }
}
