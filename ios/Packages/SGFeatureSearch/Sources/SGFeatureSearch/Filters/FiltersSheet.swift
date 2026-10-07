import SGCore
import SGDesign
import SGModels
import SwiftUI

public struct FiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.grantsDataSource) private var dataSource
    @Binding private var filters: SearchFilters
    @State private var draftFilters: SearchFilters
    @State private var facetCounts: [String: [String: Int]] = [:]
    @State private var resultCount: Int?
    @State private var countTask: Task<Void, Never>?

    private let query: String?
    private let onApply: (() -> Void)?

    public init(filters: Binding<SearchFilters>) {
        self.init(filters: filters, query: nil, onApply: nil)
    }

    public init(filters: Binding<SearchFilters>, query: String?, onApply: (() -> Void)? = nil) {
        _filters = filters
        _draftFilters = State(initialValue: filters.wrappedValue)
        self.query = query
        self.onApply = onApply
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(FilterGroup.allCases, id: \.self) { group in
                        groupView(group)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            footer
        }
        .background(.white)
        .task {
            await updateResultCount()
        }
        .onChange(of: draftFilters) { _, _ in
            scheduleCountUpdate()
        }
        .onChange(of: query) { _, _ in
            scheduleCountUpdate()
        }
        .onDisappear {
            countTask?.cancel()
        }
    }

    private var header: some View {
        HStack {
            Button("search.filters.reset".localized(bundle: .module)) {
                draftFilters = SearchFilters()
                scheduleCountUpdate()
            }
            .font(SearchTheme.F.sans(16, .medium))
            .foregroundStyle(SearchTheme.C.navy)
            .frame(minWidth: 64, minHeight: 44, alignment: .leading)
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.filters.reset")

            Spacer()
            Text("search.filters.title".localized(bundle: .module))
                .font(SearchTheme.F.sans(17, .semibold))
                .foregroundStyle(SearchTheme.C.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()

            Button("search.filters.done".localized(bundle: .module), action: commit)
                .font(SearchTheme.F.sans(16, .semibold))
                .foregroundStyle(SearchTheme.C.navy)
                .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.filters.done")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(.white)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(SearchTheme.C.line)
                .frame(height: 1)
            Button(action: commit) {
                Text(resultCount.map {
                    String.localizedStringWithFormat(
                        "search.plural.show_results".localized(bundle: .module),
                        $0
                    )
                } ?? "search.filters.show_results".localized(bundle: .module))
                    .font(SearchTheme.F.button)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(SearchTheme.C.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.filters.show_results")
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.white)
    }

    private func groupView(_ group: FilterGroup) -> some View {
        let agencies = facetCounts[group.facetKey].map { Array($0.keys) } ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Text(group.titleKey.localized(bundle: .module).uppercased())
                .font(SearchTheme.F.sans(13, .semibold))
                .tracking(0.78)
                .foregroundStyle(SearchTheme.C.muted)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)

            SearchFlowLayout(spacing: 8) {
                ForEach(SearchFilterCatalog.options(in: group, agencyCodes: agencies)) { option in
                    filterChip(option)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
    }

    private func filterChip(_ option: FilterOption) -> some View {
        let selected = SearchFilterCatalog.isSelected(option, in: draftFilters)
        let count = SearchFilterCatalog.facetCount(option, facets: facetCounts)
        let title = filterTitle(option)
        return Button {
            SearchFilterCatalog.toggle(option, in: &draftFilters)
            scheduleCountUpdate()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(SearchTheme.F.sans(14, .medium))
                if let count {
                    Text("\(count)")
                        .font(SearchTheme.F.sans(13))
                        .foregroundStyle(selected ? .white.opacity(0.76) : SearchTheme.C.muted)
                }
            }
            .foregroundStyle(selected ? .white : SearchTheme.C.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .padding(.vertical, 4)
            .background(selected ? SearchTheme.C.navy : .white, in: Capsule())
            .overlay(Capsule().stroke(selected ? SearchTheme.C.navy : SearchTheme.C.control, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filterAccessibilityLabel(title: title, count: count, selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("search.filters.option.\(option.group.rawValue).\(option.id)")
    }

    private func filterTitle(_ option: FilterOption) -> String {
        if !option.titleKey.isEmpty {
            return option.titleKey.localized(bundle: .module)
        }
        return option.values[0]
    }

    private func filterAccessibilityLabel(title: String, count: Int?, selected: Bool) -> String {
        guard let count else {
            return selected
                ? String(format: "search.filters.option_selected_accessibility".localized(bundle: .module), title)
                : title
        }
        return String(
            format: (selected
                ? "search.filters.option_accessibility_selected"
                : "search.filters.option_accessibility")
                .localized(bundle: .module),
            title,
            count
        )
    }

    private func commit() {
        filters = draftFilters
        onApply?()
        dismiss()
    }

    private func scheduleCountUpdate() {
        countTask?.cancel()
        countTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            await updateResultCount()
        }
    }

    @MainActor
    private func updateResultCount() async {
        let cleanedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = SearchRequest(
            query: cleanedQuery?.isEmpty == false ? cleanedQuery : nil,
            queryOperator: "AND",
            filters: draftFilters,
            pagination: SearchPagination(pageSize: 1)
        )
        do {
            let response = try await dataSource.searchOpportunities(request)
            resultCount = response.paginationInfo.totalRecords ?? response.data.count
            facetCounts = response.facetCounts
        } catch {
            resultCount = nil
        }
    }
}
