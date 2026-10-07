import SGModels

public struct ParsedIntent: Sendable, Hashable {
    public var searchQuery: String
    public var inferredFilters: [InferredFilter]

    public init(searchQuery: String, inferredFilters: [InferredFilter] = []) {
        self.searchQuery = searchQuery
        self.inferredFilters = inferredFilters
    }
}

public struct InferredFilter: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case applicantType
        case fundingCategory
        case status
    }

    public let kind: Kind
    public let value: String
    public let label: String
    public let matchedTerm: String

    public var id: String { "\(kind.rawValue):\(value)" }

    public init(kind: Kind, value: String, label: String, matchedTerm: String) {
        self.kind = kind
        self.value = value
        self.label = label
        self.matchedTerm = matchedTerm
    }
}

public struct AskAnswer: Sendable, Hashable {
    public let question: String
    public let intent: ParsedIntent
    public let paragraphs: [AnswerParagraph]
    public let citations: [Citation]
    public let totalMatches: Int

    public init(
        question: String,
        intent: ParsedIntent,
        paragraphs: [AnswerParagraph],
        citations: [Citation],
        totalMatches: Int
    ) {
        self.question = question
        self.intent = intent
        self.paragraphs = paragraphs
        self.citations = citations
        self.totalMatches = totalMatches
    }
}

public struct AnswerParagraph: Sendable, Hashable {
    public let segments: [AnswerSegment]

    public init(segments: [AnswerSegment]) {
        self.segments = segments
    }
}

public struct AnswerSegment: Sendable, Hashable {
    public let text: String
    public let citationIndex: Int?

    public init(text: String, citationIndex: Int? = nil) {
        self.text = text
        self.citationIndex = citationIndex
    }
}

public struct Citation: Sendable, Hashable, Identifiable {
    public let index: Int
    public let opportunity: Opportunity

    public var id: Int { index }

    public init(index: Int, opportunity: Opportunity) {
        self.index = index
        self.opportunity = opportunity
    }
}
