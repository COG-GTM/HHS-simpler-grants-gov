import SGModels

public protocol AskAnswering: Sendable {
    func answer(_ question: String, removing: Set<InferredFilter>) async throws -> AskAnswer
}

public struct AskEngine: AskAnswering {
    private let dataSource: any GrantsDataSource

    public init(dataSource: any GrantsDataSource) {
        self.dataSource = dataSource
    }

    public func answer(_ question: String, removing: Set<InferredFilter> = []) async throws -> AskAnswer {
        AskAnswer(
            question: question,
            intent: ParsedIntent(searchQuery: question),
            paragraphs: [],
            citations: [],
            totalMatches: 0
        )
    }
}
