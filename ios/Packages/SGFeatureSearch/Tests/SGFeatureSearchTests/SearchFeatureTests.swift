import Foundation
import SGFeatureSearch
import SGModels
import XCTest

@MainActor
final class SearchFeatureTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_331_200)

    func testOpportunityDisplayStatusBoundaries() {
        XCTAssertEqual(status(closeDate: "2026-10-21"), .closingSoon(daysLeft: 14))
        XCTAssertEqual(status(closeDate: "2026-10-22"), .open)
        XCTAssertEqual(status(closeDate: "2026-10-07"), .closingSoon(daysLeft: 0))
        XCTAssertEqual(status(closeDate: "2026-10-06"), .closed)
        XCTAssertEqual(status(closeDate: nil), .open)
        XCTAssertEqual(status(.forecasted), .forecasted)
        XCTAssertEqual(status(.archived), .closed)
        XCTAssertEqual(status(.closed), .closed)
    }

    func testSearchFormatting() {
        XCTAssertEqual(SearchFormatting.fullCurrency(1_000_000), "$1,000,000")
        XCTAssertEqual(SearchFormatting.compactCurrency(1_000_000), "$1M")
        XCTAssertEqual(SearchFormatting.compactCurrency(500_000), "$500K")
        XCTAssertEqual(SearchFormatting.compactCurrency(1_500_000), "$1.5M")
        XCTAssertEqual(SearchFormatting.compactCurrency(10_000), "$10K")
        XCTAssertEqual(SearchFormatting.compactCurrency(950), "$950")
        XCTAssertEqual(SearchFormatting.awardRange(floor: 10_000, ceiling: 100_000), "$10K–$100K")
        XCTAssertEqual(SearchFormatting.awardRange(floor: nil, ceiling: 100_000), "Up to $100K")
        XCTAssertEqual(SearchFormatting.awardRange(floor: 10_000, ceiling: nil), "From $10K")
        XCTAssertEqual(SearchFormatting.awardRange(floor: nil, ceiling: nil), "—")
        XCTAssertEqual(SearchFormatting.shortDate(date("2026-12-12")), "Dec 12, 2026")
    }

    func testHTMLTextStripsTagsDecodesEntitiesAndPreservesLists() {
        XCTAssertEqual(
            HTMLText.plainText(from: "<p>A &amp; B<br>next</p><ul><li>&lt;x&gt;</li><li>&#39;ok&#39;</li></ul>"),
            "A & B\nnext\n• <x>\n• 'ok'"
        )
        XCTAssertEqual(HTMLText.plainText(from: "<div><p>one</p><p>two</p></div>"), "one\ntwo")
        XCTAssertEqual(HTMLText.plainText(from: "x&nbsp;y &#65; &#x1F642;"), "x y A 🙂")
    }

    func testFilterCatalogTogglesAndCounts() {
        let nonprofits = option(.applicantType, "nonprofits")
        var filters = SearchFilters()
        SearchFilterCatalog.toggle(nonprofits, in: &filters)
        XCTAssertEqual(filters.applicantType, [
            "nonprofits_non_higher_education_with_501c3",
            "nonprofits_non_higher_education_without_501c3"
        ])
        XCTAssertTrue(SearchFilterCatalog.isSelected(nonprofits, in: filters))
        XCTAssertEqual(SearchFilterCatalog.activeCount(filters), 1)
        XCTAssertEqual(
            SearchFilterCatalog.facetCount(
                nonprofits,
                facets: ["applicant_type": [
                    "nonprofits_non_higher_education_with_501c3": 4,
                    "nonprofits_non_higher_education_without_501c3": 7
                ]]
            ),
            11
        )
        XCTAssertNil(SearchFilterCatalog.facetCount(nonprofits, facets: [:]))
        SearchFilterCatalog.toggle(nonprofits, in: &filters)
        XCTAssertTrue(filters.applicantType.isEmpty)
    }

    func testRecentSearchStoreDeduplicatesCapsPersistsAndClears() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RecentSearchStore(defaults: defaults, limit: 2)
        store.record("  clean water ")
        store.updateCount(9, for: "CLEAN WATER")
        store.record("Clean Water")
        store.record("housing")
        store.record("parks")
        XCTAssertEqual(store.items.map(\.query), ["parks", "housing"])

        let persisted = RecentSearchStore(defaults: defaults, limit: 2)
        XCTAssertEqual(persisted.items, store.items)
        persisted.record(" parks ")
        XCTAssertEqual(persisted.items.first?.resultCount, nil)
        persisted.clear()
        XCTAssertTrue(persisted.items.isEmpty)
    }

    func testResultsRequestEncodingAndSortModes() async throws {
        let source = RecordingDataSource()
        let model = ResultsViewModel(
            request: SearchRequest(query: "   "),
            dataSource: source,
            now: now
        )
        let blank = try JSONSerialization.jsonObject(with: JSONEncoder.sg.encode(model.makeRequest(page: 1))) as! [String: Any]
        XCTAssertNil(blank["query"])

        await model.toggle(.open)
        await model.toggle(.forecasted)
        let request = model.makeRequest(page: 1)
        XCTAssertEqual(request.filters.opportunityStatus, ["posted", "forecasted"])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder.sg.encode(request)) as! [String: Any]
        let filters = encoded["filters"] as! [String: [String: [String]]]
        XCTAssertEqual(filters["opportunity_status"]?["one_of"], ["posted", "forecasted"])

        let applicantOption = option(.applicantType, "nonprofits")
        var selectedFilters = SearchFilters()
        SearchFilterCatalog.toggle(applicantOption, in: &selectedFilters)
        let nonprofitRequest = SearchRequest(filters: selectedFilters)
        let nonprofitJSON = try JSONSerialization.jsonObject(with: JSONEncoder.sg.encode(nonprofitRequest)) as! [String: Any]
        let nonprofitFilters = nonprofitJSON["filters"] as! [String: [String: [String]]]
        XCTAssertEqual(
            nonprofitFilters["applicant_type"]?["one_of"],
            ["nonprofits_non_higher_education_with_501c3", "nonprofits_non_higher_education_without_501c3"]
        )

        for (sort, field, direction) in [
            (SearchSort.closeDate, "close_date", "ascending"),
            (.newest, "post_date", "descending"),
            (.awardCeiling, "award_ceiling", "descending"),
            (.title, "opportunity_title", "ascending"),
            (.relevance, "relevancy", "descending")
        ] {
            await model.setSort(sort)
            let sortOrder = model.makeRequest(page: 1).pagination.sortOrder
            XCTAssertEqual(sortOrder, [SortOrder(orderBy: field, sortDirection: direction)])
            XCTAssertEqual(SearchSort(sortOrder: sortOrder), sort)
        }
    }

    func testClosingSoonRequestAddsPostedAndUsesCloseDateSort() {
        let model = ResultsViewModel(
            request: SearchRequest(
                filters: SearchFilters(opportunityStatus: ["forecasted"]),
                pagination: SearchPagination(sortOrder: [SortOrder(orderBy: "post_date", sortDirection: "descending")])
            ),
            dataSource: RecordingDataSource(),
            now: now
        )
        model.closingSoonOnly = true
        let request = model.makeRequest(page: 1)
        XCTAssertEqual(request.filters.opportunityStatus, ["forecasted", "posted"])
        XCTAssertEqual(request.pagination.sortOrder, SearchSort.closeDate.sortOrder)
    }

    func testClosingSoonLoadFetchesPastPagesWithoutCardTrigger() async {
        let noCloseDateOne = opportunity(id: "no-close-date-one")
        let noCloseDateTwo = opportunity(id: "no-close-date-two")
        let closingSoon = opportunity(id: "closing-soon", closeDate: "2026-10-09")
        let source = RecordingDataSource(responses: [
            response([noCloseDateOne, noCloseDateTwo], page: 1, pages: 2, total: 3),
            response([closingSoon], page: 2, pages: 2, total: 3)
        ])
        let model = ResultsViewModel(
            request: SearchRequest(),
            dataSource: source,
            pageSize: 20,
            now: now
        )
        model.closingSoonOnly = true

        await model.load()

        XCTAssertEqual(model.displayedResults.map(\.id), ["closing-soon"])
        let requests = await source.recordedRequests()
        XCTAssertEqual(requests.map(\.pagination.pageOffset), [1, 2])
    }

    func testClosingSoonCountCompletesAfterPastWindowPageTail() async {
        let closingSoon = opportunity(id: "closing-soon", closeDate: "2026-10-09")
        let outsideWindow = opportunity(id: "outside-window", closeDate: "2026-10-26")
        let source = RecordingDataSource(responses: [
            response([closingSoon, outsideWindow], page: 1, pages: 3, total: 6)
        ])
        let model = ResultsViewModel(
            request: SearchRequest(),
            dataSource: source,
            pageSize: 5,
            now: now
        )
        model.closingSoonOnly = true

        await model.load()

        XCTAssertEqual(model.displayedResults.map(\.id), ["closing-soon"])
        XCTAssertTrue(model.closingSoonCountIsComplete)
        let requests = await source.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testResultsPaginationDeduplicatesAndStopsAtLastPage() async {
        let first = opportunity(id: "one")
        let second = opportunity(id: "two")
        let third = opportunity(id: "three")
        let source = RecordingDataSource(responses: [
            response([first, second], page: 1, pages: 2, total: 3),
            response([second, third], page: 2, pages: 2, total: 3)
        ])
        let model = ResultsViewModel(request: SearchRequest(), dataSource: source, pageSize: 2, now: now)
        await model.load()
        await model.loadMoreIfNeeded(currentItem: second)
        XCTAssertEqual(model.results.map(\.id), ["one", "two", "three"])
        let requests = await source.recordedRequests()
        XCTAssertEqual(requests.map(\.pagination.pageOffset), [1, 2])
        await model.loadMoreIfNeeded(currentItem: third)
        let recordedRequests = await source.recordedRequests()
        XCTAssertEqual(recordedRequests.count, 2)
    }

    func testResultsEmptyAndPageErrors() async {
        let empty = ResultsViewModel(
            request: SearchRequest(),
            dataSource: RecordingDataSource(responses: [response([], page: 1, pages: 1, total: 0)]),
            now: now
        )
        await empty.load()
        XCTAssertEqual(empty.phase, .empty)

        let failed = ResultsViewModel(
            request: SearchRequest(),
            dataSource: RecordingDataSource(searchError: .offline),
            now: now
        )
        await failed.load()
        XCTAssertEqual(failed.phase, .failed(.offline))

        let first = opportunity(id: "one")
        let pageTwoError = ResultsViewModel(
            request: SearchRequest(),
            dataSource: RecordingDataSource(
                responses: [response([first], page: 1, pages: 2, total: 2)],
                searchErrorAfterResponses: .offline
            ),
            pageSize: 1,
            now: now
        )
        await pageTwoError.load()
        await pageTwoError.loadMoreIfNeeded(currentItem: first)
        XCTAssertEqual(pageTwoError.results.map(\.id), ["one"])
        XCTAssertEqual(pageTwoError.loadMoreError, .offline)
    }

    func testSubmitFailureClearsPreviousResults() async {
        let previous = opportunity(id: "previous")
        let source = RecordingDataSource(
            responses: [response([previous], page: 1, pages: 1, total: 1)],
            searchErrorAfterResponses: .offline
        )
        let model = ResultsViewModel(request: SearchRequest(), dataSource: source, now: now)

        await model.load()
        XCTAssertEqual(model.results.map(\.id), ["previous"])

        await model.submit(query: "new query")

        XCTAssertTrue(model.results.isEmpty)
        XCTAssertEqual(model.totalRecords, 0)
        XCTAssertEqual(model.phase, .failed(.offline))
    }

    func testClearSearchAndFiltersReloadsWithoutQuery() async {
        let match = opportunity(id: "match-after-clear")
        let source = RecordingDataSource(responses: [
            response([], page: 1, pages: 1, total: 0),
            response([match], page: 1, pages: 1, total: 1)
        ])
        let model = ResultsViewModel(
            request: SearchRequest(query: "zzzz", filters: SearchFilters(fundingCategory: ["health"])),
            dataSource: source,
            now: now
        )

        await model.load()
        XCTAssertEqual(model.phase, .empty)

        await model.clearSearchAndFilters()

        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.results.map(\.id), ["match-after-clear"])
        XCTAssertEqual(model.phase, .loaded)
        let requests = await source.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests[1].query)
    }

    func testApplyingFiltersRestartsAtFirstPage() async {
        let first = opportunity(id: "first")
        let filtered = opportunity(id: "filtered")
        let source = RecordingDataSource(responses: [
            response([first], page: 1, pages: 3, total: 3),
            response([filtered], page: 1, pages: 1, total: 1)
        ])
        let model = ResultsViewModel(request: SearchRequest(), dataSource: source, pageSize: 1, now: now)
        await model.load()
        await model.apply(filters: SearchFilters(fundingCategory: ["health"]))
        XCTAssertEqual(model.results.map(\.id), ["filtered"])
        let requests = await source.recordedRequests()
        XCTAssertEqual(requests.map(\.pagination.pageOffset), [1, 1])
    }

    func testStaleResultsDoNotReplaceNewerQuery() async {
        let source = RecordingDataSource()
        let model = ResultsViewModel(
            request: SearchRequest(query: "stale"),
            dataSource: source,
            now: now
        )
        let oldLoad = Task { await model.load() }
        await source.waitForRequest(query: "stale")
        await model.submit(query: "fresh")
        await oldLoad.value
        XCTAssertEqual(model.query, "fresh")
        XCTAssertEqual(model.results.map(\.id), ["fresh"])
    }

    func testApplyCTABranchesAndShareURL() {
        let posted = opportunity(id: "open")
        let enabled = Competition(competitionId: "c1", isOpen: true, isSimplerGrantsEnabled: true)
        let detail = OpportunityDetail(opportunity: posted, competitions: [enabled])
        XCTAssertEqualCTA(ApplyCTA.resolve(detail: detail, session: .signedOut, now: now), .signInToApply)
        if case .startApplication(let competition) = ApplyCTA.resolve(
            detail: detail,
            session: .signedIn(UserProfile(userId: "u", email: "u@example.org")),
            now: now
        ) {
            XCTAssertEqual(competition, enabled)
        } else {
            XCTFail("Expected an application CTA")
        }

        let grantsGovDetail = OpportunityDetail(opportunity: opportunity(id: "external", legacyId: 123))
        if case .applyOnGrantsGov(let url) = ApplyCTA.resolve(detail: grantsGovDetail, session: .guest, now: now) {
            XCTAssertEqual(url.absoluteString, "https://www.grants.gov/search-results-detail/123")
        } else {
            XCTFail("Expected a Grants.gov CTA")
        }
        XCTAssertEqual(
            ApplyCTA.shareURL(opportunityId: "open").absoluteString,
            "https://simpler.grants.gov/opportunity/open"
        )
        XCTAssertEqualCTA(
            ApplyCTA.resolve(
                detail: OpportunityDetail(opportunity: opportunity(id: "forecasted", status: .forecasted)),
                session: .guest,
                now: now
            ),
            .notYetOpen
        )
        XCTAssertEqualCTA(
            ApplyCTA.resolve(
                detail: OpportunityDetail(opportunity: opportunity(id: "closed", status: .closed)),
                session: .guest,
                now: now
            ),
            .closed
        )
    }

    func testDetailSavedStateFailureRollsBackAndSavedLookupFailureIsNonfatal() async {
        let source = RecordingDataSource(
            detail: OpportunityDetail(opportunity: opportunity(id: "saved")),
            savedLookupError: .offline,
            saveError: .offline
        )
        let model = OpportunityDetailViewModel(opportunityId: "saved", dataSource: source, now: now)
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertFalse(model.isSaved)
        await model.toggleSaved()
        XCTAssertFalse(model.isSaved)
        XCTAssertEqual(model.saveError, .offline)
    }

    func testSecondBookmarkToggleIsIgnoredWhileSaveIsInFlight() async {
        let source = RecordingDataSource(
            detail: OpportunityDetail(opportunity: opportunity(id: "bookmark")),
            holdSave: true
        )
        let model = OpportunityDetailViewModel(opportunityId: "bookmark", dataSource: source, now: now)
        await model.load()

        let firstToggle = Task { await model.toggleSaved() }
        await source.waitForSave()
        XCTAssertTrue(model.isSavingBookmark)
        XCTAssertTrue(model.isSaved)

        await model.toggleSaved()

        XCTAssertTrue(model.isSaved)
        await source.releaseSave()
        await firstToggle.value

        XCTAssertFalse(model.isSavingBookmark)
        XCTAssertTrue(model.isSaved)
        let saveCallCount = await source.saveCallCount()
        XCTAssertEqual(saveCallCount, 1)
    }

    func testStartApplicationUsesFirstOrganizationAndOpportunityTitle() async {
        let detail = OpportunityDetail(
            opportunity: opportunity(id: "application"),
            competitions: [Competition(
                competitionId: "competition",
                isOpen: true,
                isSimplerGrantsEnabled: true
            )]
        )
        let organization = Organization(organizationId: "first-organization")
        let source = RecordingDataSource(
            detail: detail,
            organizations: [organization],
            applicationId: "created-application"
        )
        let model = OpportunityDetailViewModel(
            opportunityId: "application",
            dataSource: source,
            now: now
        )
        await model.load()
        let result = await model.startApplication(detail.competitions[0])
        XCTAssertEqual(result, "created-application")
        let start = await source.lastStartApplication()
        XCTAssertEqual(start?.name, "Test application")
        XCTAssertEqual(start?.organizationId, "first-organization")
    }

    private func status(
        _ status: OpportunityStatus = .posted,
        closeDate: String? = nil
    ) -> OpportunityDisplayStatus {
        OpportunityDisplayStatus.resolve(opportunity(id: "status", status: status, closeDate: closeDate), now: now)
    }

    private func opportunity(
        id: String,
        status: OpportunityStatus = .posted,
        closeDate: String? = nil,
        legacyId: Int? = nil
    ) -> Opportunity {
        Opportunity(
            opportunityId: id,
            opportunityNumber: "TEST-\(id)",
            opportunityTitle: "Test \(id)",
            opportunityStatus: status,
            summary: OpportunitySummary(closeDate: closeDate),
            legacyOpportunityId: legacyId
        )
    }

    private func option(_ group: FilterGroup, _ id: String) -> FilterOption {
        SearchFilterCatalog.options(in: group).first { $0.id == id }!
    }

    private func response(
        _ data: [Opportunity],
        page: Int,
        pages: Int,
        total: Int
    ) -> SearchResponse {
        SearchResponse(
            data: data,
            paginationInfo: PaginationInfo(pageOffset: page, totalPages: pages, totalRecords: total),
            facetCounts: [:]
        )
    }

    private static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }

    private func date(_ string: String) -> Date {
        Self.date(string)
    }

    private func XCTAssertEqualCTA(_ actual: ApplyCTA, _ expected: ExpectedCTA, file: StaticString = #filePath, line: UInt = #line) {
        switch (actual, expected) {
        case (.signInToApply, .signInToApply), (.closed, .closed), (.notYetOpen, .notYetOpen):
            break
        default:
            XCTFail("Unexpected CTA", file: file, line: line)
        }
    }

    private enum ExpectedCTA {
        case signInToApply
        case closed
        case notYetOpen
    }
}

private actor RecordingDataSource: GrantsDataSource {
    private var responses: [SearchResponse]
    private var requests: [SearchRequest] = []
    private var searchError: GrantsError?
    private let searchErrorAfterResponses: GrantsError?
    private let detail: OpportunityDetail?
    private let savedLookupError: GrantsError?
    private let saveError: GrantsError?
    private let holdSave: Bool
    private let organizationsToReturn: [Organization]
    private let applicationId: String
    private var lastStart: (competitionId: String, name: String, organizationId: String?)?
    private var requestWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var hasSaveStarted = false
    private var saveStartWaiter: CheckedContinuation<Void, Never>?
    private var saveCompletion: CheckedContinuation<Void, Never>?
    private var saveCalls = 0

    init(
        responses: [SearchResponse] = [],
        searchError: GrantsError? = nil,
        searchErrorAfterResponses: GrantsError? = nil,
        detail: OpportunityDetail? = nil,
        savedLookupError: GrantsError? = nil,
        saveError: GrantsError? = nil,
        holdSave: Bool = false,
        organizations: [Organization] = [],
        applicationId: String = "application"
    ) {
        self.responses = responses
        self.searchError = searchError
        self.searchErrorAfterResponses = searchErrorAfterResponses
        self.detail = detail
        self.savedLookupError = savedLookupError
        self.saveError = saveError
        self.holdSave = holdSave
        organizationsToReturn = organizations
        self.applicationId = applicationId
    }

    func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        requests.append(request)
        requestWaiters.removeValue(forKey: request.query ?? "")?.resume()
        if request.query == "stale" {
            try await Task.sleep(for: .milliseconds(100))
            let stale = Opportunity(
                opportunityId: "stale",
                opportunityStatus: .posted,
                summary: OpportunitySummary()
            )
            return SearchResponse(
                data: [stale],
                paginationInfo: PaginationInfo(pageOffset: 1, totalPages: 1, totalRecords: 1),
                facetCounts: [:]
            )
        }
        if request.query == "fresh" {
            let fresh = Opportunity(
                opportunityId: "fresh",
                opportunityStatus: .posted,
                summary: OpportunitySummary()
            )
            return SearchResponse(
                data: [fresh],
                paginationInfo: PaginationInfo(pageOffset: 1, totalPages: 1, totalRecords: 1),
                facetCounts: [:]
            )
        }
        if let searchError, responses.isEmpty { throw searchError }
        if !responses.isEmpty { return responses.removeFirst() }
        if let searchErrorAfterResponses { throw searchErrorAfterResponses }
        return SearchResponse(
            data: [],
            paginationInfo: PaginationInfo(pageOffset: request.pagination.pageOffset, totalPages: 1, totalRecords: 0),
            facetCounts: [:]
        )
    }

    func recordedRequests() -> [SearchRequest] { requests }
    func lastStartApplication() -> (competitionId: String, name: String, organizationId: String?)? { lastStart }

    func waitForRequest(query: String) async {
        if requests.contains(where: { $0.query == query }) { return }
        await withCheckedContinuation { continuation in
            requestWaiters[query] = continuation
        }
    }

    func opportunity(id: String) async throws -> OpportunityDetail {
        guard let detail else { throw GrantsError.notFound }
        return detail
    }

    func currentUser() async throws -> UserProfile { throw GrantsError.notFound }
    func organizations() async throws -> [Organization] { organizationsToReturn }
    func applications() async throws -> [ApplicationSummary] { throw GrantsError.notFound }
    func startApplication(competitionId: String, name: String, organizationId: String?) async throws -> String {
        lastStart = (competitionId, name, organizationId)
        return applicationId
    }
    func application(id: String) async throws -> Application { throw GrantsError.notFound }
    func form(id: String) async throws -> FormDefinition { throw GrantsError.notFound }
    func saveForm(applicationId: String, formId: String, response: JSONValue) async throws -> FormSaveResult { throw GrantsError.notFound }
    func submit(applicationId: String) async throws -> SubmissionResult { throw GrantsError.notFound }

    func savedOpportunityIds() async throws -> Set<String> {
        if let savedLookupError { throw savedLookupError }
        return []
    }

    func setSaved(_ saved: Bool, opportunityId: String) async throws {
        saveCalls += 1
        if holdSave {
            hasSaveStarted = true
            saveStartWaiter?.resume()
            saveStartWaiter = nil
            await withCheckedContinuation { saveCompletion = $0 }
        }
        if let saveError { throw saveError }
    }

    func waitForSave() async {
        if hasSaveStarted { return }
        await withCheckedContinuation { saveStartWaiter = $0 }
    }

    func releaseSave() {
        saveCompletion?.resume()
        saveCompletion = nil
    }

    func saveCallCount() -> Int { saveCalls }
}
