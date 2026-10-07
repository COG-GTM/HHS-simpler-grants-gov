import SGAsk
import SGModels
import XCTest
@testable import SGFeatureAsk

final class AskHomeLogicTests: XCTestCase {
    func testRecentQuestionsTrimsIgnoresEmptyDeduplicatesAndCapsAtFive() {
        XCTAssertEqual(
            RecentQuestions.adding(
                "  New question  ",
                to: ["new QUESTION", " second ", "", "third", "fourth", "fifth", "sixth"]
            ),
            ["New question", "second", "third", "fourth", "fifth"]
        )
        XCTAssertEqual(RecentQuestions.adding(" \n ", to: ["one"]), ["one"])
    }

    func testRecentQuestionsEncodeDecodeRoundTripAndBadInput() {
        let questions = ["one", "two"]
        XCTAssertEqual(RecentQuestions.decode(RecentQuestions.encode(questions)), questions)
        XCTAssertEqual(RecentQuestions.decode(""), [])
        XCTAssertEqual(RecentQuestions.decode("{not json"), [])
    }

    func testAskComposerNormalizesWhitespaceAndNewlines() {
        XCTAssertEqual(AskComposer.normalized("  rural\nclinic\r\nfunding  "), "rural clinic funding")
        XCTAssertNil(AskComposer.normalized(" \n\t "))
    }

    func testEligibilityEngineQuestionAddsOnlyMissingTerms() {
        XCTAssertEqual(EligibilityOption.nonprofit.engineQuestion(for: "Rural clinic"), "Rural clinic nonprofit")
        XCTAssertEqual(EligibilityOption.any.engineQuestion(for: "Rural clinic"), "Rural clinic")
        XCTAssertEqual(
            EligibilityOption.localGovernment.engineQuestion(for: "Local government clinic"),
            "Local government clinic"
        )
    }

    func testCitationMetaFormatsStatusDateAndAgency() {
        let locale = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(
            CitationMeta.text(for: opportunity(
                agencyCode: "HHS-HRSA",
                status: .posted,
                summary: OpportunitySummary(closeDate: "2026-12-12")
            ), locale: locale),
            "HHS · HRSA · Closes Dec 12"
        )
        XCTAssertEqual(
            CitationMeta.text(for: opportunity(
                agencyName: "National Science Foundation",
                status: .forecasted,
                summary: OpportunitySummary(forecastedCloseDate: "2027-03-15")
            ), locale: locale),
            "National Science Foundation · Forecasted Mar 2027"
        )
        XCTAssertEqual(
            CitationMeta.text(for: opportunity(
                agencyCode: "USDA",
                status: .closed,
                summary: OpportunitySummary(closeDate: "2026-10-30")
            ), locale: locale),
            "USDA · Closed Oct 30"
        )
        XCTAssertEqual(
            CitationMeta.text(for: opportunity(
                agencyCode: "NSF",
                status: .posted,
                summary: OpportunitySummary()
            ), locale: locale),
            "NSF"
        )
        XCTAssertEqual(
            CitationMeta.text(for: opportunity(
                status: .forecasted,
                summary: OpportunitySummary()
            ), locale: locale),
            ""
        )
    }

    func testAnswerSearchRequestMapsAndRemovesInferredFilters() {
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
        let secondCategory = InferredFilter(
            kind: .fundingCategory,
            value: "agriculture",
            label: "Agriculture",
            matchedTerm: "farm"
        )
        let removedCategory = InferredFilter(
            kind: .fundingCategory,
            value: "research",
            label: "Research",
            matchedTerm: "research"
        )
        let status = InferredFilter(
            kind: .status,
            value: "posted",
            label: "Open",
            matchedTerm: "open"
        )
        let answer = makeAnswer(
            searchQuery: "rural health",
            filters: [applicant, applicant, category, secondCategory, category, removedCategory, status, status]
        )
        let sameIDRemoval = InferredFilter(
            kind: .fundingCategory,
            value: "research",
            label: "Different label",
            matchedTerm: "different term"
        )

        let request = AnswerSearchRequest.make(answer: answer, removing: [sameIDRemoval])

        XCTAssertEqual(request.query, "rural health")
        XCTAssertEqual(request.queryOperator, "AND")
        XCTAssertEqual(request.filters.applicantType, ["nonprofit"])
        XCTAssertEqual(request.filters.fundingCategory, ["health", "agriculture"])
        XCTAssertEqual(request.filters.opportunityStatus, ["posted"])
    }

    func testAnswerSearchRequestExcludesDroppedFilters() {
        let applicant = InferredFilter(
            kind: .applicantType,
            value: "nonprofit",
            label: "Nonprofits",
            matchedTerm: "nonprofit"
        )
        let droppedCategory = InferredFilter(
            kind: .fundingCategory,
            value: "health",
            label: "Health",
            matchedTerm: "clinic"
        )
        let droppedCategoryMetadata = InferredFilter(
            kind: .fundingCategory,
            value: "health",
            label: "Dropped health filter",
            matchedTerm: "different term"
        )
        let answer = makeAnswer(
            searchQuery: "rural health",
            filters: [applicant, droppedCategory],
            droppedFilters: [droppedCategoryMetadata]
        )

        let request = AnswerSearchRequest.make(answer: answer, removing: [])

        XCTAssertEqual(request.filters.applicantType, ["nonprofit"])
        XCTAssertEqual(request.filters.fundingCategory, [])
    }

    func testAnswerSearchRequestOmitsDroppedOrWhitespaceOnlyQuery() {
        let droppedQuery = makeAnswer(
            searchQuery: "rural clinic",
            filters: [],
            droppedSearchQuery: true
        )
        let whitespaceQuery = makeAnswer(searchQuery: " \n ", filters: [])

        XCTAssertNil(AnswerSearchRequest.make(answer: droppedQuery, removing: []).query)
        XCTAssertNil(AnswerSearchRequest.make(answer: whitespaceQuery, removing: []).query)
    }

    func testAnswerSearchRequestUsesDefaultStatusesWithoutInferredStatus() {
        let applicant = InferredFilter(
            kind: .applicantType,
            value: "nonprofit",
            label: "Nonprofits",
            matchedTerm: "nonprofit"
        )
        let answer = makeAnswer(searchQuery: "rural clinic", filters: [applicant])

        let request = AnswerSearchRequest.make(answer: answer, removing: [])

        XCTAssertEqual(request.filters.opportunityStatus, ["posted", "forecasted"])
    }

    func testAnswerSearchRequestUsesInferredStatusesInsteadOfDefaults() {
        let status = InferredFilter(
            kind: .status,
            value: "forecasted",
            label: "Forecasted",
            matchedTerm: "upcoming"
        )
        let answer = makeAnswer(searchQuery: "rural clinic", filters: [status])

        let request = AnswerSearchRequest.make(answer: answer, removing: [])

        XCTAssertEqual(request.filters.opportunityStatus, ["forecasted"])
    }

    func testSpokenParagraphIncludesCitationSource() {
        let citedOpportunity = opportunity(
            status: .posted,
            summary: OpportunitySummary()
        )
        let paragraph = AnswerParagraph(segments: [
            AnswerSegment(text: "A program"),
            AnswerSegment(text: " funds clinics", citationIndex: 1),
            AnswerSegment(text: ".")
        ])
        let citations = [Citation(index: 1, opportunity: citedOpportunity)]

        XCTAssertEqual(
            SpokenParagraph.text(for: paragraph, citations: citations),
            "A program funds clinics, source 1."
        )
    }

    private func opportunity(
        agencyCode: String? = nil,
        agencyName: String? = nil,
        status: OpportunityStatus,
        summary: OpportunitySummary
    ) -> Opportunity {
        Opportunity(
            opportunityId: "test",
            agencyCode: agencyCode,
            agencyName: agencyName,
            opportunityStatus: status,
            summary: summary
        )
    }

    private func makeAnswer(
        searchQuery: String,
        filters: [InferredFilter],
        droppedFilters: [InferredFilter] = [],
        droppedSearchQuery: Bool = false
    ) -> AskAnswer {
        AskAnswer(
            question: searchQuery,
            intent: ParsedIntent(searchQuery: searchQuery, inferredFilters: filters),
            paragraphs: [],
            citations: [],
            totalMatches: 1,
            droppedFilters: droppedFilters,
            droppedSearchQuery: droppedSearchQuery
        )
    }
}
