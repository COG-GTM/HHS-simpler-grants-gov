import Foundation
import NaturalLanguage
import SGModels

public protocol AskReranking: Sendable {
    func rerank(question: String, candidates: [Opportunity]) -> [Opportunity]
}

/// Offline, non-generative semantic ordering for opportunity candidates.
public struct SentenceEmbeddingReranker: AskReranking {
    private let vectorProvider: @Sendable (String) -> [Double]?

    public init() {
        vectorProvider = { text in Self.defaultVector(text) }
    }

    init(vectorProvider: @escaping @Sendable (String) -> [Double]?) {
        self.vectorProvider = vectorProvider
    }

    public func rerank(question: String, candidates: [Opportunity]) -> [Opportunity] {
        guard let questionVector = vectorProvider(question) else { return candidates }
        var scored: [(index: Int, score: Double, opportunity: Opportunity)] = []
        for (index, opportunity) in candidates.enumerated() {
            let title = opportunity.opportunityTitle ?? ""
            let description = opportunity.summary.summaryDescription ?? ""
            let text = [title, description].filter { !$0.isEmpty }.joined(separator: " ")
            guard let candidateVector = vectorProvider(text),
                  let score = cosineSimilarity(questionVector, candidateVector) else {
                return candidates
            }
            scored.append((index, score, opportunity))
        }
        return scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.index < $1.index
        }.map(\.opportunity)
    }

    private static func defaultVector(_ text: String) -> [Double]? {
        EmbeddingCache.embedding?.vector(for: text)
    }

    private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        let dot = zip(lhs, rhs).reduce(0.0) { $0 + ($1.0 * $1.1) }
        let lhsMagnitude = sqrt(lhs.reduce(0.0) { $0 + ($1 * $1) })
        let rhsMagnitude = sqrt(rhs.reduce(0.0) { $0 + ($1 * $1) })
        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return nil }
        return dot / (lhsMagnitude * rhsMagnitude)
    }
}

private enum EmbeddingCache {
    static let embedding = NLEmbedding.sentenceEmbedding(for: .english)
}
