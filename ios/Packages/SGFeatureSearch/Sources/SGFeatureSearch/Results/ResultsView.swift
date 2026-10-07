import SGCore
import SGDesign
import SGModels
import SwiftUI

public struct ResultsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.grantsDataSource) private var dataSource
    @State private var viewModel: ResultsViewModel?
    @State private var queryField = ""
    @State private var isFiltersPresented = false
    @State private var draftFilters = SearchFilters()
    @State private var lastRecentCountQuery: String?

    private let request: SearchRequest?

    public init(request: SearchRequest) {
        self.request = request
        _viewModel = State(initialValue: nil)
    }

    public init(viewModel: ResultsViewModel) {
        request = nil
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        Group {
            if let viewModel {
                resultsContent(viewModel)
            } else {
                VStack(spacing: 0) {
                    DemoBanner()
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(SearchTheme.C.canvas)
            }
        }
        .background(SearchTheme.C.canvas)
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task {
            guard viewModel == nil else { return }
            let model = ResultsViewModel(request: request ?? SearchRequest(), dataSource: dataSource)
            viewModel = model
            queryField = model.query
            await model.load()
        }
        .onChange(of: viewModel?.phase) { _, phase in
            guard (phase == .loaded || phase == .empty), let viewModel else { return }
            let query = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                !query.isEmpty,
                SearchFilterCatalog.activeCount(viewModel.filters) == 0,
                !viewModel.closingSoonOnly,
                lastRecentCountQuery != query
            else {
                return
            }
            RecentSearchStore.shared.updateCount(viewModel.totalRecords, for: query)
            lastRecentCountQuery = query
        }
        .sheet(isPresented: $isFiltersPresented) {
            if let viewModel {
                FiltersSheet(
                    filters: $draftFilters,
                    query: viewModel.query,
                    onApply: {
                        Task { await viewModel.apply(filters: draftFilters) }
                    }
                )
                .presentationDetents([.fraction(0.76), .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func resultsContent(_ viewModel: ResultsViewModel) -> some View {
        VStack(spacing: 0) {
            DemoBanner()
            header(viewModel)
            quickFilters(viewModel)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    metaRow(viewModel)
                    switch viewModel.phase {
                    case .idle where viewModel.results.isEmpty,
                         .loading where viewModel.results.isEmpty:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    case .empty:
                        let actionTitle = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "search.results.clear_filters"
                            : "search.results.clear_search_and_filters"
                        EmptyStateView(
                            title: "search.results.empty_title".localized(bundle: .module),
                            message: "search.results.empty_message".localized(bundle: .module),
                            actionTitle: actionTitle.localized(bundle: .module),
                            action: {
                                queryField = ""
                                Task { await viewModel.clearSearchAndFilters() }
                            }
                        )
                        .accessibilityIdentifier("search.results.clear_filters")
                        if viewModel.closingSoonOnly {
                            endOfListSentinel(viewModel)
                        }
                    case let .failed(error) where viewModel.results.isEmpty:
                        InlineErrorBanner(
                            message: errorMessage(error),
                            retry: { Task { await viewModel.load() } }
                        )
                        .accessibilityIdentifier("search.results.retry")
                    case .loaded where viewModel.closingSoonOnly && viewModel.displayedResults.isEmpty:
                        if viewModel.closingSoonCountIsComplete {
                            EmptyStateView(
                                title: "search.results.empty_title".localized(bundle: .module),
                                message: "search.results.empty_message".localized(bundle: .module),
                                actionTitle: "search.results.clear_filters".localized(bundle: .module),
                                action: { Task { await viewModel.clearFilters() } }
                            )
                            .accessibilityIdentifier("search.results.clear_filters")
                        } else if let error = viewModel.loadMoreError {
                            InlineErrorBanner(
                                message: errorMessage(error),
                                retry: { Task { await viewModel.loadNextPageIfAvailable() } }
                            )
                            .accessibilityIdentifier("search.results.retry")
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                        }
                        endOfListSentinel(viewModel)
                    default:
                        if case let .failed(error) = viewModel.phase {
                            InlineErrorBanner(
                                message: errorMessage(error),
                                retry: { Task { await viewModel.load() } }
                            )
                            .accessibilityIdentifier("search.results.retry")
                        }
                        ForEach(viewModel.displayedResults) { opportunity in
                            opportunityCard(opportunity, now: viewModel.now)
                                .onAppear {
                                    Task { await viewModel.loadMoreIfNeeded(currentItem: opportunity) }
                                }
                        }
                        endOfListSentinel(viewModel)
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        if let error = viewModel.loadMoreError {
                            InlineErrorBanner(
                                message: errorMessage(error),
                                retry: {
                                    Task {
                                        if let last = viewModel.results.last {
                                            await viewModel.loadMoreIfNeeded(currentItem: last)
                                        }
                                    }
                                }
                            )
                            .accessibilityIdentifier("search.results.retry")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .refreshable { await viewModel.refresh() }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(SearchTheme.C.canvas)
    }

    private func header(_ viewModel: ResultsViewModel) -> some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SearchTheme.C.navy)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("search.navigation.back".localized(bundle: .module))

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SearchTheme.C.muted)
                    .accessibilityHidden(true)
                TextField("search.field.placeholder".localized(bundle: .module), text: $queryField)
                    .font(SearchTheme.F.bodyText)
                    .foregroundStyle(SearchTheme.C.ink)
                    .submitLabel(.search)
                    .onSubmit {
                        Task {
                            RecentSearchStore.shared.record(queryField)
                            lastRecentCountQuery = nil
                            await viewModel.submit(query: queryField)
                        }
                    }
                    .accessibilityIdentifier("search.results.field")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(SearchTheme.C.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func quickFilters(_ viewModel: ResultsViewModel) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    draftFilters = viewModel.filters
                    isFiltersPresented = true
                } label: {
                    Text(viewModel.activeFilterCount == 0
                         ? "search.results.filters".localized(bundle: .module)
                         : String(format: "search.results.filters_count".localized(bundle: .module), viewModel.activeFilterCount))
                        .font(SearchTheme.F.sans(14, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .padding(.vertical, 5)
                        .background(SearchTheme.C.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.results.filters")

                ForEach(QuickStatus.allCases) { status in
                    Button {
                        Task { await viewModel.toggle(status) }
                    } label: {
                        SearchChip(
                            label: status.titleKey.localized(bundle: .module),
                            selected: viewModel.isSelected(status)
                        )
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: viewModel.isSelected(status))
                    .accessibilityAddTraits(viewModel.isSelected(status) ? .isSelected : [])
                    .accessibilityIdentifier("search.results.chip.\(status.id == "closingSoon" ? "closing_soon" : status.id)")
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 12)
    }

    private func metaRow(_ viewModel: ResultsViewModel) -> some View {
        let hasEmptyError: Bool
        if case .failed = viewModel.phase, viewModel.results.isEmpty {
            hasEmptyError = true
        } else {
            hasEmptyError = false
        }
        let countKey = viewModel.closingSoonOnly && !viewModel.closingSoonCountIsComplete
            ? "search.plural.opportunities_at_least"
            : "search.plural.opportunities"
        return HStack {
            if !hasEmptyError {
                Text(String.localizedStringWithFormat(
                    countKey.localized(bundle: .module),
                    viewModel.closingSoonOnly ? viewModel.displayedResults.count : viewModel.totalRecords
                ))
                .foregroundStyle(SearchTheme.C.muted)
            }
            Spacer()
            Menu {
                Picker("search.results.sort_picker".localized(bundle: .module), selection: Binding(
                    get: { viewModel.sort },
                    set: { sort in Task { await viewModel.setSort(sort) } }
                )) {
                    ForEach(SearchSort.allCases) { sort in
                        Text(sort.titleKey.localized(bundle: .module)).tag(sort)
                    }
                }
            } label: {
                Text(String(format: "search.results.sort_label".localized(bundle: .module), viewModel.sort.titleKey.localized(bundle: .module)))
                    .foregroundStyle(SearchTheme.C.navy)
                    .frame(minHeight: 44, alignment: .trailing)
            }
            .accessibilityIdentifier("search.results.sort")
        }
        .font(SearchTheme.F.caption)
        .padding(.horizontal, 4)
    }

    private func endOfListSentinel(_ viewModel: ResultsViewModel) -> some View {
        Color.clear
            .frame(height: 1)
            .onAppear { Task { await viewModel.loadNextPageIfAvailable() } }
            .accessibilityHidden(true)
    }

    private func opportunityCard(_ opportunity: Opportunity, now: Date) -> some View {
        let status = OpportunityDisplayStatus.resolve(opportunity, now: now)
        let agency = opportunity.agencyName ?? opportunity.topLevelAgencyName ?? "search.format.unavailable".localized(bundle: .module)
        let closeDate = status == .forecasted
            ? opportunity.summary.forecastedCloseDateValue ?? opportunity.summary.closeDateValue
            : opportunity.summary.closeDateValue
        let close = closeDate.map(SearchFormatting.shortDate) ?? "search.format.unavailable".localized(bundle: .module)
        let award = SearchFormatting.awardRange(floor: opportunity.summary.awardFloor, ceiling: opportunity.summary.awardCeiling)
        let unavailable = "search.format.not_available".localized(bundle: .module)
        let accessibilityText = String(
            format: "search.results.card_accessibility".localized(bundle: .module),
            status.statusChipKey.localized(bundle: .module),
            opportunity.opportunityTitle ?? unavailable,
            opportunity.agencyName ?? opportunity.topLevelAgencyName ?? unavailable,
            closeDate.map(SearchFormatting.shortDate) ?? unavailable,
            award == "—" ? unavailable : award
        )

        return Button {
            router.push(.opportunity(id: opportunity.id))
        } label: {
            SearchCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        HStack(spacing: 8) {
                            StatusChip(status: status.statusChipKey)
                            if case let .closingSoon(daysLeft) = status {
                                Text(String.localizedStringWithFormat(
                                    "search.plural.days_left".localized(bundle: .module),
                                    daysLeft
                                ))
                                .font(SearchTheme.F.caption)
                                .foregroundStyle(SearchTheme.C.soonFg)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(opportunity.opportunityNumber ?? "search.format.unavailable".localized(bundle: .module))
                            .font(SearchTheme.F.mono)
                            .foregroundStyle(SearchTheme.C.subtle)
                            .lineLimit(1)
                    }

                    Text(opportunity.opportunityTitle ?? "search.format.unavailable".localized(bundle: .module))
                        .font(SearchTheme.F.cardTitle)
                        .foregroundStyle(SearchTheme.C.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)

                    Text(agency)
                        .font(SearchTheme.F.sans(14))
                        .foregroundStyle(SearchTheme.C.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)

                    Rectangle()
                        .fill(SearchTheme.C.lineSoft)
                        .frame(height: 1)
                        .padding(.top, 2)
                        .accessibilityHidden(true)

                    HStack(alignment: .top, spacing: 16) {
                        resultFact(label: "search.results.closes".localized(bundle: .module), value: close)
                        resultFact(label: "search.results.award".localized(bundle: .module), value: award)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SearchTheme.R.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("search.results.card.\(opportunity.id)")
    }

    private func resultFact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SearchTheme.F.caption)
                .foregroundStyle(SearchTheme.C.subtle)
            Text(value)
                .font(SearchTheme.F.sans(13, .semibold))
                .foregroundStyle(SearchTheme.C.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value == "—"
                            ? "search.format.not_available".localized(bundle: .module)
                            : "\(label), \(value)")
    }

    private func errorMessage(_ error: GrantsError) -> String {
        let key: String
        switch error {
        case .offline: key = "search.error.offline"
        case .unauthorized: key = "search.error.unauthorized"
        case .notFound: key = "search.error.not_found"
        case .server: key = "search.error.server"
        case .decoding: key = "search.error.decoding"
        }
        return key.localized(bundle: .module)
    }
}
