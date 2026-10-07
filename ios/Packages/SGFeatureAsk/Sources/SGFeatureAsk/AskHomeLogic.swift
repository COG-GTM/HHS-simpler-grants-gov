import Foundation
import SGAsk
import SGDesign
import SGModels

enum RecentQuestions {
    static let maxCount = 5

    static func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let questions = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Array(questions.prefix(maxCount))
    }

    static func encode(_ list: [String]) -> String {
        guard let data = try? JSONEncoder().encode(list) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func adding(_ question: String, to list: [String]) -> [String] {
        guard let question = AskComposer.normalized(question) else { return list }
        var result = [question]
        for item in list {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !result.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
                continue
            }
            result.append(trimmed)
            if result.count == maxCount { break }
        }
        return result
    }
}

enum AskComposer {
    static func normalized(_ text: String) -> String? {
        let singleLine = text.replacingOccurrences(
            of: "[\\r\\n]+",
            with: " ",
            options: .regularExpression
        )
        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum EligibilityOption: String, CaseIterable, Identifiable {
    case any
    case nonprofit
    case localGovernment
    case stateGovernment
    case tribalGovernment
    case university
    case smallBusiness
    case individual

    var id: String { rawValue }

    var localizationKey: String {
        let key: String
        switch self {
        case .any: key = "any"
        case .nonprofit: key = "nonprofit"
        case .localGovernment: key = "local_government"
        case .stateGovernment: key = "state_government"
        case .tribalGovernment: key = "tribal_government"
        case .university: key = "university"
        case .smallBusiness: key = "small_business"
        case .individual: key = "individual"
        }
        return "ask.home.eligibility.\(key)"
    }

    var engineTerm: String? {
        switch self {
        case .any: return nil
        case .nonprofit: return "nonprofit"
        case .localGovernment: return "local government"
        case .stateGovernment: return "state government"
        case .tribalGovernment: return "tribal government"
        case .university: return "university"
        case .smallBusiness: return "small business"
        case .individual: return "individual"
        }
    }

    func engineQuestion(for question: String) -> String {
        guard let engineTerm,
              !question.localizedCaseInsensitiveContains(engineTerm) else {
            return question
        }
        return "\(question) \(engineTerm)"
    }
}

enum CitationMeta {
    static func text(for opportunity: Opportunity, locale: Locale = .current) -> String {
        let agency = opportunity.agencyCode?
            .replacingOccurrences(of: "-", with: " · ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
            ?? opportunity.agencyName?.nonEmpty

        let dateLabel: String?
        switch opportunity.opportunityStatus {
        case .posted:
            dateLabel = formatted(opportunity.summary.closeDate, format: "MMM d", locale: locale)
                .map { String(format: "ask.answer.meta.closes".localized(bundle: .module), $0) }
        case .forecasted:
            dateLabel = formatted(
                opportunity.summary.forecastedCloseDate ?? opportunity.summary.closeDate,
                format: "MMM yyyy",
                locale: locale
            ).map { String(format: "ask.answer.meta.forecasted".localized(bundle: .module), $0) }
        case .closed, .archived:
            dateLabel = formatted(opportunity.summary.closeDate, format: "MMM d", locale: locale)
                .map { String(format: "ask.answer.meta.closed".localized(bundle: .module), $0) }
        }

        switch (agency, dateLabel) {
        case let (agency?, dateLabel?): return "\(agency) · \(dateLabel)"
        case let (agency?, nil): return agency
        case let (nil, dateLabel?): return dateLabel
        case (nil, nil): return ""
        }
    }

    private static func formatted(_ raw: String?, format: String, locale: Locale) -> String? {
        guard let raw else { return nil }
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.dateFormat = "yyyy-MM-dd"
        inputFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = inputFormatter.date(from: raw) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = format
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

enum AnswerSearchRequest {
    static func make(intent: ParsedIntent, removing: Set<InferredFilter>) -> SearchRequest {
        var filters = SearchFilters()
        for filter in intent.inferredFilters where !removing.contains(filter) {
            switch filter.kind {
            case .applicantType:
                filters.applicantType.append(filter.value)
            case .fundingCategory:
                filters.fundingCategory.append(filter.value)
            case .status:
                filters.opportunityStatus.append(filter.value)
            }
        }
        return SearchRequest(query: intent.searchQuery, filters: filters)
    }
}

enum SpokenParagraph {
    static func text(for paragraph: AnswerParagraph, citations: [Citation]) -> String {
        let citationIndexes = Set(citations.map(\.index))
        return paragraph.segments.reduce(into: "") { spoken, segment in
            spoken += segment.text
            if let index = segment.citationIndex, citationIndexes.contains(index) {
                spoken += String(
                    format: "ask.answer.spoken_source".localized(bundle: .module),
                    index
                )
            }
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
