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
    public let now: Date

    private let dataSource: any GrantsDataSource
    private let pageSize: Int
    private var page = 1
    private var totalPages = 1
    private var generation = 0

    public init(
        request: SearchRequest,
        dataSource: any GrantsDataSource,
        pageSize: Int = 20,
        now: Date = Date()
    ) {
        query = request.query ?? ""
        filters = request.filters
        sort = SearchSort(sortOrder: request.pagination.sortOrder) ?? .closeDate
        self.dataSource = dataSource
        self.pageSize = max(1, pageSize)
        self.now = now
    }

    public var displayedResults: [Opportunity] {
        guard closingSoonOnly else { return results }
        return results.filter { OpportunityDisplayStatus.resolve($0, now: now).isClosingSoon }
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
        generation += 1
        let requestGeneration = generation
        phase = .loading
        page = 1
        loadMoreError = nil
        isLoadingMore = false
        do {
            let response = try await dataSource.searchOpportunities(makeRequest(page: 1))
            guard requestGeneration == generation else { return }
            results = response.data
            totalRecords = response.paginationInfo.totalRecords ?? response.data.count
            totalPages = response.paginationInfo.totalPages ?? max(1, Int(ceil(Double(totalRecords) / Double(pageSize))))
            facetCounts = response.facetCounts
            phase = results.isEmpty ? .empty : .loaded
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
            page < totalPages,
            !isLoadingMore
        else {
            return
        }
        isLoadingMore = true
        loadMoreError = nil
        let requestGeneration = generation
        let nextPage = page + 1
        do {
            let response = try await dataSource.searchOpportunities(makeRequest(page: nextPage))
            guard requestGeneration == generation else {
                isLoadingMore = false
                return
            }
            var seen = Set(results.map(\.id))
            results.append(contentsOf: response.data.filter { seen.insert($0.id).inserted })
            page = nextPage
            totalRecords = response.paginationInfo.totalRecords ?? totalRecords
            totalPages = response.paginationInfo.totalPages ?? totalPages
            facetCounts = response.facetCounts
            isLoadingMore = false
        } catch let error as GrantsError {
            guard requestGeneration == generation else { return }
            loadMoreError = error
            isLoadingMore = false
        } catch {
            guard requestGeneration == generation else { return }
            loadMoreError = .server(status: 500, message: error.localizedDescription)
            isLoadingMore = false
        }
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
        await load()
    }

    public func clearFilters() async {
        filters = SearchFilters()
        closingSoonOnly = false
        await load()
    }

    public func apply(filters: SearchFilters) async {
        self.filters = filters
        await load()
    }

    public func setSort(_ sort: SearchSort) async {
        self.sort = sort
        await load()
    }

    public func submit(query: String) async {
        self.query = query
        await load()
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
