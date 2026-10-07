import SGCore
import SGDesign
import SwiftUI

struct SGTabBar: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var tabIconSize = 23
    @ScaledMetric(relativeTo: .body) private var tabLabelSize = 10

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 72 : 49)
        .background(backgroundColor.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let (key, symbol, identifier) = properties(for: tab)
        let title = key.localized(bundle: .main)
        let isSelected = router.tab == tab

        return Button {
            router.select(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .symbolVariant(.none)
                    .font(.system(size: tabIconSize, weight: .regular))
                    .frame(minHeight: 25)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.custom("PublicSans-Medium", size: tabLabelSize))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(isSelected ? selectedColor : unselectedColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 72 : 49)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("shell.tab.\(identifier)")
    }

    private func properties(for tab: AppTab) -> (key: String, symbol: String, identifier: String) {
        switch tab {
        case .ask:
            return ("tabs.ask", "bubble.left", "ask")
        case .search:
            return ("tabs.search", "magnifyingglass", "search")
        case .apply:
            return ("tabs.apply", "doc.text", "apply")
        case .profile:
            return ("tabs.profile", "person", "profile")
        }
    }

    private var backgroundColor: Color {
        Color(red: 250 / 255, green: 250 / 255, blue: 248 / 255)
    }

    private var borderColor: Color {
        Color(red: 228 / 255, green: 228 / 255, blue: 223 / 255)
    }

    private var selectedColor: Color {
        Color(red: 31 / 255, green: 61 / 255, blue: 110 / 255)
    }

    private var unselectedColor: Color {
        Color(red: 90 / 255, green: 96 / 255, blue: 112 / 255)
    }
}
