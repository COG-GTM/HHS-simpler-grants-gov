import Foundation

public struct IntentParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> ParsedIntent {
        details(for: text).intent
    }

    static var keywordValues: [(InferredFilter.Kind, String)] {
        KeywordTable.load().entries.flatMap { entry in
            entry.values.map { (entry.kind, $0) }
        }
    }

    func details(for text: String) -> ParsedIntentDetails {
        let tokens = Self.tokenize(text)
        var inferredFilters: [InferredFilter] = []
        var confidenceByID: [String: Double] = [:]
        var consumed = Set<Int>()
        var sortByCloseDate = false
        var tokenIndex = 0
        let stopwords = Self.table.normalizedStopwords

        while tokenIndex < tokens.count {
            guard let match = Self.matches.first(where: { candidate in
                tokenIndex + candidate.tokens.count <= tokens.count
                    && Array(tokens[tokenIndex..<(tokenIndex + candidate.tokens.count)]) == candidate.tokens
            }) else {
                tokenIndex += 1
                continue
            }

            if match.entry.consumes {
                consumed.formUnion(tokenIndex..<(tokenIndex + match.tokens.count))
            }
            if match.entry.sortByCloseDate == true {
                sortByCloseDate = true
            }

            for value in match.entry.values {
                let id = "\(match.entry.kind.rawValue):\(value)"
                let labelKey = match.entry.sortByCloseDate == true
                    ? "ask.filter.status.closing_soon"
                    : "ask.filter.\(Self.localizationKind(match.entry.kind)).\(value)"
                let filter = InferredFilter(
                    kind: match.entry.kind,
                    value: value,
                    label: AskLocalization.text(labelKey),
                    matchedTerm: match.term
                )
                if !confidenceByID.keys.contains(id) {
                    inferredFilters.append(filter)
                    confidenceByID[id] = match.entry.confidence
                } else {
                    confidenceByID[id] = max(confidenceByID[id] ?? 0, match.entry.confidence)
                }
            }
            tokenIndex += match.tokens.count
        }

        let remaining = tokens.enumerated().compactMap { index, token -> String? in
            guard !consumed.contains(index), !stopwords.contains(token) else { return nil }
            return token
        }
        var queryTokens: [String] = []
        for token in remaining {
            let proposed = (queryTokens + [token]).joined(separator: " ")
            guard proposed.count <= 100 else { break }
            queryTokens.append(token)
        }

        return ParsedIntentDetails(
            intent: ParsedIntent(searchQuery: queryTokens.joined(separator: " "), inferredFilters: inferredFilters),
            confidenceByID: confidenceByID,
            sortByCloseDate: sortByCloseDate
        )
    }

    private static func localizationKind(_ kind: InferredFilter.Kind) -> String {
        switch kind {
        case .applicantType: "applicant_type"
        case .fundingCategory: "funding_category"
        case .status: "status"
        }
    }

    fileprivate static func tokenize(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var normalized = String.UnicodeScalarView()
        var previousWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                normalized.append(scalar)
                previousWasSpace = false
            } else if !previousWasSpace {
                normalized.append(" ")
                previousWasSpace = true
            }
        }
        return String(normalized).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static let table = KeywordTable.load()
    private static let matches: [TermMatch] = {
        table.entries.flatMap { entry in
            entry.terms.map { term in
                TermMatch(entry: entry, term: term, tokens: tokenize(term))
            }
        }.enumerated().sorted { lhs, rhs in
            if lhs.element.tokens.count != rhs.element.tokens.count {
                return lhs.element.tokens.count > rhs.element.tokens.count
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }()
}

struct ParsedIntentDetails: Sendable {
    let intent: ParsedIntent
    let confidenceByID: [String: Double]
    let sortByCloseDate: Bool
}

private struct KeywordTable: Decodable {
    let stopwords: [String]
    let entries: [KeywordEntry]

    var normalizedStopwords: Set<String> {
        Set(stopwords.flatMap(IntentParser.tokenize))
    }

    static func load() -> KeywordTable {
        guard let url = Bundle.module.url(forResource: "ask_keywords", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(KeywordTable.self, from: data) else {
            return KeywordTable(stopwords: [], entries: [])
        }
        return table
    }
}

private struct KeywordEntry: Decodable, Sendable {
    let terms: [String]
    let kind: InferredFilter.Kind
    let values: [String]
    let confidence: Double
    let consumes: Bool
    let sortByCloseDate: Bool?

    enum CodingKeys: String, CodingKey {
        case terms, kind, values, confidence, consumes
        case sortByCloseDate
    }
}

private struct TermMatch {
    let entry: KeywordEntry
    let term: String
    let tokens: [String]
}
