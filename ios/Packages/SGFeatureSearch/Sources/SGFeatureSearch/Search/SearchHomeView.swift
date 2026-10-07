import SGCore
import SGDesign
import SGModels
import SwiftUI

public struct SearchHomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.grantsDataSource) private var dataSource
    @State private var query = ""
    @State private var categoryCounts: [String: Int] = [:]
    @State private var countsLoaded = false

    private let recentStore: RecentSearchStore

    public init() {
        recentStore = .shared
    }

    public init(recentStore: RecentSearchStore) {
        self.recentStore = recentStore
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("search.home.heading".localized(bundle: .module))
                        .font(SearchTheme.F.largeTitle)
                        .foregroundStyle(SearchTheme.C.ink)
                        .accessibilityAddTraits(.isHeader)

                    searchField
                        .padding(.top, 16)

                    if !recentStore.items.isEmpty {
                        recentSection
                            .padding(.top, 28)
                    }

                    Text("search.home.browse_heading".localized(bundle: .module))
                        .font(SearchTheme.F.section)
                        .foregroundStyle(SearchTheme.C.ink)
                        .padding(.top, 28)
                        .accessibilityAddTraits(.isHeader)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(SearchFilterCatalog.browseCategories()) { category in
                            categoryTile(category)
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, SearchTheme.S.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(SearchTheme.C.canvas)
        .task {
            guard !countsLoaded else { return }
            countsLoaded = true
            await loadCategoryCounts()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(SearchTheme.C.subtle)
                .accessibilityHidden(true)
            TextField("search.field.placeholder".localized(bundle: .module), text: $query)
                .font(SearchTheme.F.sans(17))
                .foregroundStyle(SearchTheme.C.ink)
                .submitLabel(.search)
                .onSubmit(submitSearch)
                .accessibilityIdentifier("search.field")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(SearchTheme.C.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("search.home.recent_heading".localized(bundle: .module))
                    .font(SearchTheme.F.section)
                    .foregroundStyle(SearchTheme.C.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("search.home.clear".localized(bundle: .module)) {
                    recentStore.clear()
                }
                .font(SearchTheme.F.sans(15, .medium))
                .foregroundStyle(SearchTheme.C.navy)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.recent.clear")
            }

            VStack(spacing: 0) {
                ForEach(Array(recentStore.items.enumerated()), id: \.element.query) { index, recent in
                    Button {
                        runRecentSearch(recent.query)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(SearchTheme.C.subtle)
                                .accessibilityHidden(true)
                            Text(recent.query)
                                .font(SearchTheme.F.bodyText)
                                .foregroundStyle(SearchTheme.C.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            Text(recentCount(recent.resultCount))
                                .font(SearchTheme.F.caption)
                                .foregroundStyle(SearchTheme.C.subtle)
                                .multilineTextAlignment(.trailing)
                        }
                        .frame(minHeight: 44)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.recent.row")
                    if index < recentStore.items.count - 1 {
                        Rectangle()
                            .fill(SearchTheme.C.line)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func categoryTile(_ category: BrowseCategory) -> some View {
        Button {
            router.push(.results(SearchRequest(
                filters: SearchFilters(
                    opportunityStatus: ["posted"],
                    fundingCategory: category.values
                )
            )))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(category.titleKey.localized(bundle: .module))
                    .font(SearchTheme.F.sans(15, .semibold))
                    .foregroundStyle(SearchTheme.C.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let count = categoryCounts[category.id] {
                    Text(String.localizedStringWithFormat(
                        "search.plural.open_opportunities".localized(bundle: .module),
                        count
                    ))
                    .font(SearchTheme.F.caption)
                    .foregroundStyle(SearchTheme.C.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SearchTheme.C.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.category.\(category.id)")
    }

    private func submitSearch() {
        runRecentSearch(query)
    }

    private func runRecentSearch(_ value: String) {
        recentStore.record(value)
        router.push(.results(SearchRequest(query: value)))
    }

    private func recentCount(_ count: Int?) -> String {
        guard let count else { return "search.format.unavailable".localized(bundle: .module) }
        return String.localizedStringWithFormat(
            "search.plural.opportunities".localized(bundle: .module),
            count
        )
    }

    private func loadCategoryCounts() async {
        let request = SearchRequest(
            filters: SearchFilters(opportunityStatus: ["posted"]),
            pagination: SearchPagination(pageSize: 1)
        )
        guard let response = try? await dataSource.searchOpportunities(request),
              let facet = response.facetCounts["funding_category"] else {
            return
        }
        categoryCounts = Dictionary(uniqueKeysWithValues: SearchFilterCatalog.browseCategories().compactMap { category in
            let count = category.values.reduce(0) { $0 + (facet[$1] ?? 0) }
            return (category.id, count)
        })
    }
}
