import Foundation
import SGAsk
import SGModels

public struct AskPreviewEngine: AskAnswering {
    public enum Mode: Sendable {
        case answer
        case empty
        case failure
        case loading
    }

    private let mode: Mode

    public init(mode: Mode = .answer) {
        self.mode = mode
    }

    public func answer(_ question: String, removing: Set<InferredFilter>) async throws -> AskAnswer {
        switch mode {
        case .empty:
            return AskAnswer(
                question: question,
                intent: ParsedIntent(searchQuery: question),
                paragraphs: [],
                citations: [],
                totalMatches: 0
            )
        case .failure:
            throw GrantsError.offline
        case .loading:
            try await Task.sleep(for: .seconds(3_600))
            return Self.answerFixture(question, removing: removing)
        case .answer:
            return Self.answerFixture(question, removing: removing)
        }
    }

    private static func answerFixture(_ question: String, removing: Set<InferredFilter>) -> AskAnswer {
        let citations = [
            Citation(index: 1, opportunity: opportunity(
                id: "hrsa-27-014",
                number: "HRSA-27-014",
                title: "Rural Communities Opioid Response Program – Implementation",
                agencyCode: "HHS-HRSA",
                status: .posted,
                summary: OpportunitySummary(closeDate: "2026-12-12", awardCeiling: 1_000_000)
            )),
            Citation(index: 2, opportunity: opportunity(
                id: "usda-rd-27-05",
                number: "USDA-RD-27-05",
                title: "Community Facilities Technical Assistance and Training",
                agencyCode: "USDA",
                status: .posted,
                summary: OpportunitySummary(closeDate: "2026-10-30")
            )),
            Citation(index: 3, opportunity: opportunity(
                id: "nsf-27-512",
                number: "NSF 27-512",
                title: "Smart and Connected Communities",
                agencyCode: "NSF",
                status: .forecasted,
                summary: OpportunitySummary(forecastedCloseDate: "2027-03-15")
            ))
        ]
        let applicant = InferredFilter(
            kind: .applicantType,
            value: "nonprofit",
            label: "Nonprofits",
            matchedTerm: "nonprofit"
        )
        let category = InferredFilter(
            kind: .fundingCategory,
            value: "health",
            label: "Health",
            matchedTerm: "clinic"
        )
        let intent = ParsedIntent(
            searchQuery: question,
            inferredFilters: [applicant, category].filter { !removing.contains($0) }
        )
        let paragraphs = [
            AnswerParagraph(segments: [
                AnswerSegment(text: "The closest match is HRSA's "),
                AnswerSegment(text: "Rural Communities Opioid Response Program", citationIndex: 1),
                AnswerSegment(text: ". It funds nonprofits and local governments in rural areas to expand treatment and recovery services, with awards up to $1,000,000. Applications close December 12, 2026.")
            ]),
            AnswerParagraph(segments: [
                AnswerSegment(text: "USDA's "),
                AnswerSegment(text: "Community Facilities Technical Assistance", citationIndex: 2),
                AnswerSegment(text: " closes sooner, on October 30. "),
                AnswerSegment(text: "NSF's "),
                AnswerSegment(text: "Smart and Connected Communities", citationIndex: 3),
                AnswerSegment(text: " is forecasted for March 2027.")
            ])
        ]
        return AskAnswer(
            question: question,
            intent: intent,
            paragraphs: paragraphs,
            citations: citations,
            totalMatches: 214
        )
    }

    private static func opportunity(
        id: String,
        number: String,
        title: String,
        agencyCode: String,
        status: OpportunityStatus,
        summary: OpportunitySummary
    ) -> Opportunity {
        Opportunity(
            opportunityId: id,
            opportunityNumber: number,
            opportunityTitle: title,
            agencyCode: agencyCode,
            opportunityStatus: status,
            summary: summary
        )
    }
}
