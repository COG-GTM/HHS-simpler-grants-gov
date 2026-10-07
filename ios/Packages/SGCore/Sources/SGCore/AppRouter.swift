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

public enum DeepLink {
    public static func parse(_ url: URL) -> AppRoute? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let components else { return nil }

        if components.scheme?.lowercased() == "simplergrants" {
            guard components.host?.lowercased() == "opportunity" else { return nil }
            let path = components.path.split(separator: "/")
            guard path.count == 1, let identifier = path.first else { return nil }
            return .opportunity(id: String(identifier))
        }

        guard
            components.scheme?.lowercased() == "https",
            components.host?.lowercased() == "simpler.grants.gov"
        else {
            return nil
        }
        let path = components.path.split(separator: "/").map(String.init)
        guard path.count == 2, path[0] == "opportunity", !path[1].isEmpty else {
            return nil
        }
        return .opportunity(id: path[1])
    }
}

@Observable
@MainActor
public final class AppRouter {
    public var tab: AppTab
    private var paths: [AppTab: [AppRoute]]

    public init(tab: AppTab = .ask) {
        self.tab = tab
        paths = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) })
    }

    public func push(_ route: AppRoute, in tab: AppTab? = nil) {
        let tab = tab ?? self.tab
        var path = paths[tab] ?? []
        guard path.last != route else { return }
        path.append(route)
        paths[tab] = path
    }

    public func popToRoot(_ tab: AppTab) {
        paths[tab] = []
    }

    public func navigationPath(for tab: AppTab) -> NavigationPath {
        NavigationPath(routes(for: tab))
    }

    public func setNavigationPath(_ path: NavigationPath, for tab: AppTab) {
        let current = routes(for: tab)
        if path.count < current.count {
            paths[tab] = Array(current.prefix(path.count))
        }
    }

    public func binding(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { self.navigationPath(for: tab) },
            set: { self.setNavigationPath($0, for: tab) }
        )
    }

    public func routes(for tab: AppTab) -> [AppRoute] {
        paths[tab] ?? []
    }

    public func routesBinding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { self.routes(for: tab) },
            set: { routes in
                let current = self.routes(for: tab)
                if routes.count < current.count {
                    self.paths[tab] = Array(current.prefix(routes.count))
                }
            }
        )
    }

    public func select(_ tab: AppTab) {
        if self.tab == tab {
            popToRoot(tab)
        } else {
            self.tab = tab
        }
    }

    public func reset() {
        for tab in AppTab.allCases {
            popToRoot(tab)
        }
        tab = .ask
    }

    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard let route = DeepLink.parse(url) else { return false }
        tab = .search
        popToRoot(.search)
        push(route, in: .search)
        return true
    }
}
