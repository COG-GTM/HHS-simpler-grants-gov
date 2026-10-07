import Foundation
import Observation
import SGModels

@Observable
@MainActor
public final class ResultsViewModel {
    public enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(GrantsError)
    }

    public private(set) var query: String
    public private(set) var filters: SearchFilters
    public private(set) var sort: SearchSort
    public var closingSoonOnly = false
    public private(set) var results: [Opportunity] = []
    public private(set) var totalRecords = 0
    public private(set) var facetCounts: [String: [String: Int]] = [:]
    public private(set) var phase: Phase = .idle
    public private(set) var isLoadingMore = false
    public private(set) var loadMoreError: GrantsError?
    public private(set) var now: Date

    private let dataSource: any GrantsDataSource
    private let pageSize: Int
    private let clock: @Sendable () -> Date
    private var page = 1
    private var totalPages = 1
    private var lastFetchedPageLastItem: Opportunity?
    private var generation = 0

    public init(
        request: SearchRequest,
        dataSource: any GrantsDataSource,
        pageSize: Int = 20,
        now: Date? = nil
    ) {
        query = request.query ?? ""
        filters = request.filters
        sort = SearchSort(sortOrder: request.pagination.sortOrder) ?? .closeDate
        self.dataSource = dataSource
        self.pageSize = max(1, pageSize)
        if let now {
            clock = { now }
        } else {
            clock = { Date() }
        }
        self.now = clock()
    }

    public var displayedResults: [Opportunity] {
        guard closingSoonOnly else { return results }
        return results.filter { OpportunityDisplayStatus.resolve($0, now: now).isClosingSoon }
    }

    public var closingSoonCountIsComplete: Bool {
        if page >= totalPages {
            return true
        }
        guard
            let lastFetchedPageLastItem,
            let daysLeft = OpportunityDisplayStatus.daysLeft(for: lastFetchedPageLastItem, now: now)
        else {
            return false
        }
        return daysLeft > 14
    }

    public var activeFilterCount: Int {
        SearchFilterCatalog.activeCount(filters) + (closingSoonOnly ? 1 : 0)
    }

    public func makeRequest(page: Int) -> SearchRequest {
        var requestFilters = filters
        if closingSoonOnly, !requestFilters.opportunityStatus.contains("posted") {
            requestFilters.opportunityStatus.append("posted")
        }
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return SearchRequest(
            query: cleanedQuery.isEmpty ? nil : cleanedQuery,
            queryOperator: "AND",
            filters: requestFilters,
            pagination: SearchPagination(
                pageOffset: page,
                pageSize: pageSize,
                sortOrder: closingSoonOnly ? SearchSort.closeDate.sortOrder : sort.sortOrder
            )
        )
    }

    public func load() async {
        await reload(resetResults: false)
    }

    private func reload(resetResults: Bool) async {
        now = clock()
        generation += 1
        let requestGeneration = generation
        phase = .loading
        page = 1
        loadMoreError = nil
        isLoadingMore = false
        if resetResults {
            results = []
            totalRecords = 0
            facetCounts = [:]
            totalPages = 1
            lastFetchedPageLastItem = nil
        }
        do {
            let response = try await dataSource.searchOpportunities(makeRequest(page: 1))
            guard requestGeneration == generation else { return }
            results = response.data
            totalRecords = response.paginationInfo.totalRecords ?? response.data.count
            totalPages = response.paginationInfo.totalPages ?? max(1, Int(ceil(Double(totalRecords) / Double(pageSize))))
            facetCounts = response.facetCounts
            lastFetchedPageLastItem = response.data.last
            phase = results.isEmpty ? .empty : .loaded
            if closingSoonOnly {
                isLoadingMore = true
                await autoFetchClosingSoonPages(maxPages: 5, requestGeneration: requestGeneration)
                if requestGeneration == generation {
                    isLoadingMore = false
                }
            }
        } catch let error as GrantsError {
            guard requestGeneration == generation else { return }
            phase = .failed(error)
        } catch {
            guard requestGeneration == generation else { return }
            phase = .failed(.server(status: 500, message: error.localizedDescription))
        }
    }

    public func loadMoreIfNeeded(currentItem: Opportunity) async {
        guard
            let index = results.firstIndex(where: { $0.id == currentItem.id }),
            index >= max(0, results.count - 3),
            page < totalPages
        else {
            return
        }
        await loadNextPageIfAvailable()
    }

    public func loadNextPageIfAvailable() async {
        guard page < totalPages, !isLoadingMore else { return }
        guard !(closingSoonOnly && closingSoonCountIsComplete) else { return }
        isLoadingMore = true
        loadMoreError = nil
        let requestGeneration = generation
        defer {
            if requestGeneration == generation {
                isLoadingMore = false
            }
        }
        guard await fetchNextPage(requestGeneration: requestGeneration) else { return }
        if closingSoonOnly {
            await autoFetchClosingSoonPages(maxPages: 5, requestGeneration: requestGeneration)
        }
    }

    private func fetchNextPage(requestGeneration: Int) async -> Bool {
        guard requestGeneration == generation, page < totalPages else { return false }
        let nextPage = page + 1
        do {
            let response = try await dataSource.searchOpportunities(makeRequest(page: nextPage))
            guard requestGeneration == generation else { return false }
            var seen = Set(results.map(\.id))
            results.append(contentsOf: response.data.filter { seen.insert($0.id).inserted })
            page = nextPage
            totalRecords = response.paginationInfo.totalRecords ?? totalRecords
            totalPages = response.paginationInfo.totalPages ?? totalPages
            facetCounts = response.facetCounts
            lastFetchedPageLastItem = response.data.last
            phase = results.isEmpty ? .empty : .loaded
            return true
        } catch let error as GrantsError {
            guard requestGeneration == generation else { return false }
            loadMoreError = error
        } catch {
            guard requestGeneration == generation else { return false }
            loadMoreError = .server(status: 500, message: error.localizedDescription)
        }
        return false
    }

    private func autoFetchClosingSoonPages(maxPages: Int, requestGeneration: Int) async {
        var fetchedPages = 0
        while
            fetchedPages < maxPages,
            requestGeneration == generation,
            shouldAutoFetchClosingSoonPage()
        {
            guard await fetchNextPage(requestGeneration: requestGeneration) else { return }
            fetchedPages += 1
        }
    }

    private func shouldAutoFetchClosingSoonPage() -> Bool {
        guard closingSoonOnly, page < totalPages, displayedResults.count < pageSize else {
            return false
        }
        guard
            let lastFetchedPageLastItem,
            let daysLeft = OpportunityDisplayStatus.daysLeft(for: lastFetchedPageLastItem, now: now)
        else {
            return true
        }
        return daysLeft <= 14
    }

    public func refresh() async {
        await load()
    }

    public func isSelected(_ status: QuickStatus) -> Bool {
        switch status {
        case .open:
            return filters.opportunityStatus.contains("posted")
        case .closingSoon:
            return closingSoonOnly
        case .forecasted:
            return filters.opportunityStatus.contains("forecasted")
        }
    }

    public func toggle(_ status: QuickStatus) async {
        switch status {
        case .open:
            toggleValue("posted", in: &filters.opportunityStatus)
        case .closingSoon:
            closingSoonOnly.toggle()
        case .forecasted:
            toggleValue("forecasted", in: &filters.opportunityStatus)
        }
        await reload(resetResults: true)
    }

    public func clearFilters() async {
        filters = SearchFilters()
        closingSoonOnly = false
        await reload(resetResults: true)
    }

    public func clearSearchAndFilters() async {
        query = ""
        filters = SearchFilters()
        closingSoonOnly = false
        await reload(resetResults: true)
    }

    public func apply(filters: SearchFilters) async {
        self.filters = filters
        await reload(resetResults: true)
    }

    public func setSort(_ sort: SearchSort) async {
        self.sort = sort
        await reload(resetResults: true)
    }

    public func submit(query: String) async {
        self.query = query
        await reload(resetResults: true)
    }

    private func toggleValue(_ value: String, in values: inout [String]) {
        if values.contains(value) {
            values.removeAll { $0 == value }
        } else {
            values.append(value)
        }
    }
}

private extension OpportunityDisplayStatus {
    var isClosingSoon: Bool {
        if case .closingSoon = self { return true }
        return false
    }
}
