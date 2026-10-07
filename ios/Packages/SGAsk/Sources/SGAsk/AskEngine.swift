import Foundation
import SGModels

public protocol AskAnswering: Sendable {
    func answer(_ question: String, removing: Set<InferredFilter>) async throws -> AskAnswer
}

public struct AskEngine: AskAnswering {
    private let dataSource: any GrantsDataSource
    private let locale: Locale
    private let reranker: (any AskReranking)?
    private let parser: IntentParser

    public init(
        dataSource: any GrantsDataSource,
        locale: Locale = .current,
        reranker: (any AskReranking)? = SentenceEmbeddingReranker()
    ) {
        self.dataSource = dataSource
        self.locale = locale
        self.reranker = reranker
        parser = IntentParser()
    }

    public func answer(_ question: String, removing: Set<InferredFilter> = []) async throws -> AskAnswer {
        let parsed = parser.details(for: question)
        let removedIDs = Set(removing.map(\.id))
        let activeFilters = parsed.intent.inferredFilters.filter { !removedIDs.contains($0.id) }
        var sortByCloseDate = parsed.sortByCloseDate
        if removedIDs.contains("status:posted") {
            sortByCloseDate = false
        }
        let intentAfterRemoving = ParsedIntent(
            searchQuery: parsed.intent.searchQuery,
            inferredFilters: activeFilters
        )
        let confidence = parsed.confidenceByID.filter { !removedIDs.contains($0.key) }
        let defaultStatus = activeFilters.contains(where: { $0.kind == .status })
            ? []
            : ["posted", "forecasted"]
        let filters = makeFilters(activeFilters, defaultStatus: defaultStatus)
        let requestParts = SearchRequestParts(
            query: intentAfterRemoving.searchQuery.isEmpty ? nil : intentAfterRemoving.searchQuery,
            filters: filters
        )
        let requests = [
            makeRequest(parts: requestParts, queryOperator: "AND", sortByCloseDate: sortByCloseDate),
            makeRequest(parts: requestParts, queryOperator: "OR", sortByCloseDate: sortByCloseDate)
        ]

        var tried: [SearchRequest] = []
        var response: SearchResponse?
        var successfulFilters = activeFilters
        var droppedFilters: [InferredFilter] = []
        var droppedSearchQuery = false

        for (index, request) in requests.enumerated() {
            if tried.contains(where: { equivalent($0, request, singleTokenQuery: requestParts.query) }) {
                continue
            }
            tried.append(request)
            let result = try await dataSource.searchOpportunities(request)
            if !result.data.isEmpty {
                response = result
                break
            }
            if index == 1 {
                break
            }
        }

        if response == nil,
           let leastConfident = leastConfidentFilter(activeFilters, confidence: confidence) {
            let remainingFilters = activeFilters.filter { $0.id != leastConfident.id }
            let reducedRequest = makeRequest(
                parts: SearchRequestParts(
                    query: requestParts.query,
                    filters: makeFilters(
                        remainingFilters,
                        defaultStatus: remainingFilters.contains(where: { $0.kind == .status })
                            ? []
                            : defaultStatus
                    )
                ),
                queryOperator: "OR",
                sortByCloseDate: sortByCloseDate
            )
            if !tried.contains(where: { equivalent($0, reducedRequest, singleTokenQuery: requestParts.query) }) {
                tried.append(reducedRequest)
                let result = try await dataSource.searchOpportunities(reducedRequest)
                if !result.data.isEmpty {
                    response = result
                    successfulFilters = remainingFilters
                    droppedFilters = [leastConfident]
                }
            }
        }

        if response == nil,
           requestParts.query != nil,
           activeFilters.contains(where: { $0.kind == .applicantType || $0.kind == .fundingCategory }) {
            let querylessRequest = makeRequest(
                parts: SearchRequestParts(
                    query: nil,
                    filters: makeFilters(activeFilters, defaultStatus: defaultStatus)
                ),
                queryOperator: "OR",
                sortByCloseDate: sortByCloseDate
            )
            if !tried.contains(where: { equivalent($0, querylessRequest, singleTokenQuery: requestParts.query) }) {
                tried.append(querylessRequest)
                let result = try await dataSource.searchOpportunities(querylessRequest)
                if !result.data.isEmpty {
                    response = result
                    successfulFilters = activeFilters
                    droppedSearchQuery = true
                }
            }
        }

        guard let response else {
            return AskAnswer(
                question: question,
                intent: intentAfterRemoving,
                paragraphs: [],
                citations: [],
                totalMatches: 0
            )
        }

        let candidates: [Opportunity]
        if sortByCloseDate {
            candidates = response.data
        } else if let reranker {
            candidates = reranker.rerank(question: question, candidates: response.data)
        } else {
            candidates = response.data
        }
        let selected = Array(candidates.prefix(25))
        let citations = selected.compactMap { opportunity -> Opportunity? in
            guard opportunity.opportunityTitle?.isEmpty == false
                || opportunity.opportunityNumber?.isEmpty == false else { return nil }
            return opportunity
        }.prefix(3).enumerated().map { index, opportunity in
            Citation(index: index + 1, opportunity: opportunity)
        }
        let paragraphs = makeParagraphs(citations)
        let answerIntent = ParsedIntent(
            searchQuery: intentAfterRemoving.searchQuery,
            inferredFilters: successfulFilters
        )
        return AskAnswer(
            question: question,
            intent: answerIntent,
            paragraphs: paragraphs,
            citations: citations,
            totalMatches: response.paginationInfo.totalRecords ?? response.data.count,
            droppedFilters: droppedFilters,
            droppedSearchQuery: droppedSearchQuery
        )
    }

    private func makeFilters(_ filters: [InferredFilter], defaultStatus: [String]) -> SearchFilters {
        let inferredStatus = uniqueValues(for: .status, in: filters)
        return SearchFilters(
            opportunityStatus: inferredStatus.isEmpty ? defaultStatus : inferredStatus,
            applicantType: uniqueValues(for: .applicantType, in: filters),
            fundingCategory: uniqueValues(for: .fundingCategory, in: filters)
        )
    }

    private func uniqueValues(for kind: InferredFilter.Kind, in filters: [InferredFilter]) -> [String] {
        var seen = Set<String>()
        return filters.compactMap { filter in
            guard filter.kind == kind, seen.insert(filter.value).inserted else { return nil }
            return filter.value
        }
    }

    private func makeRequest(
        parts: SearchRequestParts,
        queryOperator: String,
        sortByCloseDate: Bool
    ) -> SearchRequest {
        let sort: SGModels.SortOrder
        if sortByCloseDate {
            sort = SGModels.SortOrder(orderBy: "close_date", sortDirection: "ascending")
        } else if parts.query != nil {
            sort = SGModels.SortOrder(orderBy: "relevancy", sortDirection: "descending")
        } else {
            sort = SGModels.SortOrder(orderBy: "post_date", sortDirection: "descending")
        }
        return SearchRequest(
            query: parts.query,
            queryOperator: queryOperator,
            filters: parts.filters,
            pagination: SearchPagination(pageOffset: 1, pageSize: 25, sortOrder: [sort])
        )
    }

    private func equivalent(
        _ lhs: SearchRequest,
        _ rhs: SearchRequest,
        singleTokenQuery: String?
    ) -> Bool {
        if lhs == rhs { return true }
        guard let singleTokenQuery,
              singleTokenQuery.split(whereSeparator: \.isWhitespace).count <= 1 else {
            return lhs.query == nil && rhs.query == nil
                && lhs.filters == rhs.filters
                && lhs.pagination == rhs.pagination
        }
        return lhs.query == rhs.query
            && lhs.filters == rhs.filters
            && lhs.pagination == rhs.pagination
    }

    private func leastConfidentFilter(
        _ filters: [InferredFilter],
        confidence: [String: Double]
    ) -> InferredFilter? {
        filters.enumerated()
            .filter { $0.element.kind == .applicantType || $0.element.kind == .fundingCategory }
            .min { lhs, rhs in
                let lhsConfidence = confidence[lhs.element.id] ?? 0
                let rhsConfidence = confidence[rhs.element.id] ?? 0
                if lhsConfidence != rhsConfidence {
                    return lhsConfidence < rhsConfidence
                }
                return lhs.offset > rhs.offset
            }?.element
    }

    private func makeParagraphs(_ citations: [Citation]) -> [AnswerParagraph] {
        guard let top = citations.first else { return [] }
        let topOpportunity = top.opportunity
        var firstSegments = [
            AnswerSegment(text: AskLocalization.text("ask.engine.closest_match_prefix")),
            AnswerSegment(
                text: listingName(topOpportunity),
                citationIndex: top.index,
                emphasizedText: nonempty(topOpportunity.opportunityTitle)
            )
        ]
        let topFacts = facts(for: topOpportunity)
        if topFacts.isEmpty {
            firstSegments.append(AnswerSegment(text: AskLocalization.text("ask.engine.facts_empty")))
        } else {
            firstSegments.append(
                AnswerSegment(
                    text: AskLocalization.text("ask.engine.facts_prefix") + topFacts,
                    citationIndex: top.index
                )
            )
        }
        var paragraphs = [AnswerParagraph(segments: firstSegments)]

        if citations.count > 1 {
            var otherSegments: [AnswerSegment] = []
            for citation in citations.dropFirst() {
                let opportunity = citation.opportunity
                otherSegments.append(
                    AnswerSegment(
                        text: (otherSegments.isEmpty ? "" : AskLocalization.text("ask.engine.sentence_separator"))
                            + listingName(opportunity),
                        citationIndex: citation.index,
                        emphasizedText: nonempty(opportunity.opportunityTitle)
                    )
                )
                otherSegments.append(
                    AnswerSegment(
                        text: otherSentence(opportunity, top: topOpportunity),
                        citationIndex: citation.index
                    )
                )
            }
            paragraphs.append(AnswerParagraph(segments: otherSegments))
        }
        return paragraphs
    }

    private func facts(for opportunity: Opportunity) -> String {
        let summary = opportunity.summary
        let applicants = summary.applicantTypes?.map {
            localizedLabel("ask.label.applicant_type.\($0)", fallback: $0)
        } ?? []
        let categories = summary.fundingCategories?.map {
            localizedLabel("ask.label.funding_category.\($0)", fallback: $0)
        } ?? []
        let applicantList = list(applicants)
        let categoryList = list(categories)
        let award = summary.awardCeiling.map(formatMoney)
        var result = ""

        switch (applicantList, categoryList, award) {
        case let (.some(applicants), .some(categories), .some(award)):
            result = AskLocalization.format("ask.engine.facts.applicants_categories_award", locale: locale, applicants, categories, award)
        case let (.some(applicants), .some(categories), .none):
            result = AskLocalization.format("ask.engine.facts.applicants_categories", locale: locale, applicants, categories)
        case let (.some(applicants), .none, .some(award)):
            result = AskLocalization.format("ask.engine.facts.applicants_award", locale: locale, applicants, award)
        case let (.some(applicants), .none, .none):
            result = AskLocalization.format("ask.engine.facts.applicants", locale: locale, applicants)
        case let (.none, .some(categories), .some(award)):
            result = AskLocalization.format("ask.engine.facts.categories_award", locale: locale, categories, award)
        case let (.none, .some(categories), .none):
            result = AskLocalization.format("ask.engine.facts.categories", locale: locale, categories)
        case let (.none, .none, .some(award)):
            result = AskLocalization.format("ask.engine.facts.award", locale: locale, award)
        case (.none, .none, .none):
            break
        }

        if opportunity.opportunityStatus == .posted, let closeDate = summary.closeDateValue {
            result += AskLocalization.format(
                "ask.engine.date.applications_close",
                locale: locale,
                formatDate(closeDate, style: .long)
            )
        } else if opportunity.opportunityStatus == .forecasted {
            if let postDate = parseDate(summary.forecastedPostDate) {
                result += AskLocalization.format(
                    "ask.engine.date.forecasted_open",
                    locale: locale,
                    formatDate(postDate, template: "MMMMy")
                )
            } else if let closeDate = summary.forecastedCloseDateValue {
                result += AskLocalization.format(
                    "ask.engine.date.forecasted_close",
                    locale: locale,
                    formatDate(closeDate, style: .long)
                )
            }
        }
        return result
    }

    private func otherSentence(_ opportunity: Opportunity, top: Opportunity) -> String {
        let summary = opportunity.summary
        if opportunity.opportunityStatus == .forecasted {
            if let postDate = parseDate(summary.forecastedPostDate) {
                return AskLocalization.format(
                    "ask.engine.other.forecasted_open",
                    locale: locale,
                    formatDate(postDate, template: "MMMMy")
                )
            }
            if let closeDate = summary.forecastedCloseDateValue {
                return AskLocalization.format(
                    "ask.engine.other.forecasted_close",
                    locale: locale,
                    formatDate(closeDate, style: .long)
                )
            }
            return AskLocalization.text("ask.engine.other.forecasted")
        }

        if opportunity.opportunityStatus == .posted,
           let closeDate = summary.closeDateValue,
           let topCloseDate = top.summary.closeDateValue,
           closeDate < topCloseDate {
            return AskLocalization.format(
                "ask.engine.other.closes_sooner",
                locale: locale,
                formatDate(closeDate, template: "MMMMd")
            )
        }
        if let award = summary.awardCeiling,
           let topAward = top.summary.awardCeiling,
           award > topAward {
            return AskLocalization.format(
                "ask.engine.other.larger_awards",
                locale: locale,
                formatMoney(award)
            )
        }
        if let closeDate = summary.closeDateValue {
            return AskLocalization.format(
                "ask.engine.other.closes",
                locale: locale,
                formatDate(closeDate, style: .long)
            )
        }
        return AskLocalization.text("ask.engine.other.also_match")
    }

    private func listingName(_ opportunity: Opportunity) -> String {
        let title = nonempty(opportunity.opportunityTitle) ?? nonempty(opportunity.opportunityNumber) ?? ""
        guard let agency = agencyDisplay(opportunity) else { return title }
        return AskLocalization.format("ask.engine.name_with_agency", locale: locale, agency, title)
    }

    private func agencyDisplay(_ opportunity: Opportunity) -> String? {
        if let code = nonempty(opportunity.agencyCode) {
            let lastComponent = code.split(separator: "-").last.map(String.init)
            if let lastComponent, !lastComponent.isEmpty { return lastComponent }
        }
        return nonempty(opportunity.agencyName)
    }

    private func localizedLabel(_ key: String, fallback: String) -> String {
        let value = AskLocalization.text(key)
        return value == key ? fallback.replacingOccurrences(of: "_", with: " ") : value
    }

    private func list(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values)
    }

    private func formatMoney(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = locale
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func formatDate(_ date: Date, style: DateFormatter.Style? = nil, template: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let style {
            formatter.dateStyle = style
            formatter.timeStyle = .none
        } else if let template {
            formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale)
        }
        return formatter.string(from: date)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private struct SearchRequestParts {
    let query: String?
    let filters: SearchFilters
}
