import Foundation
@testable import SGAsk
import SGModels
import XCTest

final class AskEngineTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    func testTryAskingPrompts() {
        let parser = IntentParser()
        let prompts: [(String, String, [String])] = [
            (
                "Grants for a rural health clinic",
                "rural health clinic",
                ["fundingCategory:agriculture", "fundingCategory:health"]
            ),
            (
                "Arts funding for a small nonprofit",
                "arts",
                ["fundingCategory:arts", "applicantType:nonprofits_non_higher_education_with_501c3"]
            ),
            (
                "Climate resilience projects for my city",
                "climate resilience",
                [
                    "fundingCategory:environment",
                    "fundingCategory:disaster_prevention_and_relief",
                    "applicantType:city_or_township_governments"
                ]
            ),
            (
                "Research funding for early-career scientists",
                "research early career scientists",
                ["fundingCategory:science_technology_and_other_research_and_development"]
            )
        ]

        for (question, query, ids) in prompts {
            let parsed = parser.parse(question)
            XCTAssertEqual(parsed.searchQuery, query, question)
            XCTAssertEqual(parsed.inferredFilters.map(\.id), ids, question)
        }
    }

    func testParserPhraseNormalizationAndEmptyInput() {
        let parser = IntentParser()
        XCTAssertEqual(parser.parse("small business").inferredFilters.map(\.id), ["applicantType:small_businesses"])
        XCTAssertEqual(parser.parse("small business").searchQuery, "")

        let closingSoon = parser.details(for: "closing soon")
        XCTAssertEqual(closingSoon.intent.inferredFilters.map(\.id), ["status:posted"])
        XCTAssertEqual(closingSoon.intent.inferredFilters.first?.label, "Closing soon")
        XCTAssertTrue(closingSoon.sortByCloseDate)
        XCTAssertEqual(parser.parse("open now").inferredFilters.map(\.id), ["status:posted"])
        XCTAssertEqual(parser.parse("Café—non-profit!").searchQuery, "cafe")
        XCTAssertEqual(
            parser.parse("Café—non-profit!").inferredFilters.map(\.id),
            ["applicantType:nonprofits_non_higher_education_with_501c3"]
        )
        XCTAssertEqual(parser.parse("  \n\t ").searchQuery, "")
        XCTAssertTrue(parser.parse("  \n\t ").inferredFilters.isEmpty)
        XCTAssertEqual(parser.parse(String(repeating: "x ", count: 80)).searchQuery.count, 99)
    }

    func testAllInferredValuesAreOpenAPIEnums() {
        let applicantTypes: Set<String> = [
            "state_governments", "county_governments", "city_or_township_governments",
            "special_district_governments", "independent_school_districts",
            "public_and_state_institutions_of_higher_education",
            "private_institutions_of_higher_education",
            "federally_recognized_native_american_tribal_governments",
            "other_native_american_tribal_organizations", "public_and_indian_housing_authorities",
            "nonprofits_non_higher_education_with_501c3", "nonprofits_non_higher_education_without_501c3",
            "individuals", "for_profit_organizations_other_than_small_businesses", "small_businesses",
            "other", "unrestricted"
        ]
        let fundingCategories: Set<String> = [
            "recovery_act", "agriculture", "arts", "business_and_commerce", "community_development",
            "consumer_protection", "disaster_prevention_and_relief", "education",
            "employment_labor_and_training", "energy", "environment", "food_and_nutrition", "health",
            "housing", "humanities", "infrastructure_investment_and_jobs_act",
            "information_and_statistics", "income_security_and_social_services",
            "law_justice_and_legal_services", "natural_resources", "opportunity_zone_benefits",
            "regional_development", "science_technology_and_other_research_and_development",
            "transportation", "affordable_care_act", "other",
            "energy_infrastructure_and_critical_mineral_and_materials", "recreation_and_tourism"
        ]
        for (kind, value) in IntentParser.keywordValues {
            switch kind {
            case .applicantType:
                XCTAssertTrue(applicantTypes.contains(value), value)
            case .fundingCategory:
                XCTAssertTrue(fundingCategories.contains(value), value)
            case .status:
                XCTAssertTrue(["posted", "forecasted"].contains(value), value)
            }
        }
    }

    func testR1FallsBackToR2AndKeepsStatusDefault() async throws {
        let source = FakeGrantsDataSource(responses: [
            .empty,
            .response([sample(title: "Found result")], total: 4)
        ])
        let answer = try await engine(source).answer("health clinic")
        let requests = await source.recordedRequests()

        XCTAssertEqual(requests.map(\.queryOperator), ["AND", "OR"])
        XCTAssertEqual(requests.first?.filters.opportunityStatus, ["posted", "forecasted"])
        XCTAssertEqual(requests.first?.pagination.sortOrder.count, 1)
        XCTAssertEqual(requests.first?.pagination.pageSize, 25)
        XCTAssertTrue(requests.allSatisfy { !$0.pagination.sortOrder.isEmpty })
        XCTAssertEqual(answer.totalMatches, 4)
        XCTAssertEqual(answer.intent.inferredFilters.map(\.id), ["fundingCategory:health"])
        XCTAssertCitationInvariant(answer)
    }

    func testR3DropsLeastConfidentNonStatusFilter() async throws {
        let source = FakeGrantsDataSource(responses: [
            .empty, .empty, .response([sample(title: "Found result")], total: 1)
        ])
        let answer = try await engine(source).answer("climate resilience my city")
        let requests = await source.recordedRequests()

        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[2].queryOperator, "OR")
        XCTAssertEqual(requests[2].filters.applicantType, [])
        XCTAssertEqual(
            answer.droppedFilters.map(\.id),
            ["applicantType:city_or_township_governments"]
        )
        XCTAssertFalse(answer.intent.inferredFilters.contains { $0.id == "applicantType:city_or_township_governments" })
        XCTAssertEqual(answer.intent.inferredFilters.map(\.id), [
            "fundingCategory:environment",
            "fundingCategory:disaster_prevention_and_relief"
        ])
        XCTAssertCitationInvariant(answer)
    }

    func testSingleWordQuerySkipsEquivalentORRequest() async throws {
        let source = FakeGrantsDataSource(responses: [.empty, .response([sample(title: "Found result")], total: 1)])
        let answer = try await engine(source).answer("open housing")
        let requests = await source.recordedRequests()

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].query, "housing")
        XCTAssertEqual(requests[1].queryOperator, "OR")
        XCTAssertTrue(requests[1].filters.fundingCategory.isEmpty)
        XCTAssertCitationInvariant(answer)
    }

    func testEmptyResultsAndStatusSortBehavior() async throws {
        let emptySource = FakeGrantsDataSource(responses: [.empty, .empty, .empty])
        let emptyAnswer = try await engine(emptySource).answer("rural clinic")
        XCTAssertTrue(emptyAnswer.paragraphs.isEmpty)
        XCTAssertTrue(emptyAnswer.citations.isEmpty)
        XCTAssertEqual(emptyAnswer.totalMatches, 0)
        XCTAssertCitationInvariant(emptyAnswer)

        let closingSource = FakeGrantsDataSource(responses: [.response([sample(title: "Closing")], total: 1)])
        let closingAnswer = try await engine(closingSource).answer("closing soon")
        let closingRequest = await closingSource.recordedRequests().first
        XCTAssertEqual(closingRequest?.filters.opportunityStatus, ["posted"])
        XCTAssertEqual(closingRequest?.pagination.sortOrder.first?.orderBy, "close_date")
        XCTAssertEqual(closingRequest?.pagination.sortOrder.first?.sortDirection, "ascending")
        XCTAssertNil(closingRequest?.query)
        XCTAssertCitationInvariant(closingAnswer)

        let removedSource = FakeGrantsDataSource(responses: [.response([sample(title: "Open")], total: 1)])
        let closingFilter = IntentParser().parse("closing soon").inferredFilters[0]
        _ = try await engine(removedSource).answer("closing soon", removing: [closingFilter])
        let removedRequest = await removedSource.recordedRequests().first
        XCTAssertEqual(removedRequest?.filters.opportunityStatus, ["posted", "forecasted"])
        XCTAssertEqual(removedRequest?.pagination.sortOrder.first?.orderBy, "post_date")
    }

    func testRemovingFilterChangesRequestAndIntent() async throws {
        let source = FakeGrantsDataSource(responses: [.response([sample(title: "Result")], total: 1)])
        let health = IntentParser().parse("health clinic").inferredFilters[0]
        let answer = try await engine(source).answer("health clinic", removing: [health])
        let request = await source.recordedRequests().first

        XCTAssertTrue(request?.filters.fundingCategory.isEmpty == true)
        XCTAssertFalse(answer.intent.inferredFilters.contains { $0.id == health.id })
        XCTAssertCitationInvariant(answer)
    }

    func testCitationInvariantsAndMissingFields() async throws {
        let first = sample(
            title: "Complete listing",
            number: "DEMO-1",
            code: "HHS-HRSA",
            status: .posted,
            summary: OpportunitySummary(
                closeDate: "2026-12-12",
                awardCeiling: 1_000_000,
                applicantTypes: ["nonprofits_non_higher_education_with_501c3", "county_governments"],
                fundingCategories: ["health", "agriculture"]
            )
        )
        let second = sample(
            title: nil,
            number: "DEMO-2",
            code: nil,
            status: .posted,
            summary: OpportunitySummary()
        )
        let ignored = sample(title: nil, number: nil)
        let source = FakeGrantsDataSource(responses: [.response([first, second, ignored], total: 3)])
        let answer = try await engine(source).answer("health")

        XCTAssertEqual(answer.citations.map(\.index), [1, 2])
        XCTAssertTrue(render(answer).contains("HRSA's Complete listing"))
        XCTAssertTrue(render(answer).contains("DEMO-2"))
        XCTAssertTrue(render(answer).contains("1,000,000"))
        XCTAssertCitationInvariant(answer)

        let onlyInvalidSource = FakeGrantsDataSource(responses: [.response([ignored], total: 1)])
        let onlyInvalidAnswer = try await engine(onlyInvalidSource).answer("health")
        XCTAssertTrue(onlyInvalidAnswer.paragraphs.isEmpty)
        XCTAssertTrue(onlyInvalidAnswer.citations.isEmpty)
    }

    func testFormattingUsesEngineLocale() async throws {
        let listing = sample(
            title: "Formatting",
            status: .posted,
            summary: OpportunitySummary(closeDate: "2026-12-12", awardCeiling: 1_000_000)
        )
        let englishSource = FakeGrantsDataSource(responses: [.response([listing], total: 1)])
        let english = try await engine(englishSource).answer("health")
        XCTAssertCitationInvariant(english)
        XCTAssertTrue(render(english).contains("$1,000,000"))
        XCTAssertTrue(render(english).contains("December 12, 2026"))

        let germanSource = FakeGrantsDataSource(responses: [.response([listing], total: 1)])
        let german = try await AskEngine(
            dataSource: germanSource,
            locale: Locale(identifier: "de_DE"),
            reranker: nil
        ).answer("health")
        XCTAssertCitationInvariant(german)
        XCTAssertTrue(render(german).contains("1.000.000"))
        XCTAssertTrue(render(german).contains("Dezember"))
    }

    func testRerankerStableOrderingAndNilFallback() {
        let questionVector = [1.0, 0.0]
        let first = sample(title: "First")
        let second = sample(title: "Second")
        let reranker = SentenceEmbeddingReranker(vectorProvider: { text in
            if text == "question" { return questionVector }
            if text.hasPrefix("First") { return [0.0, 1.0] }
            return [1.0, 0.0]
        })
        XCTAssertEqual(reranker.rerank(question: "question", candidates: [first, second]).map(\.id), [second.id, first.id])

        let unavailable = SentenceEmbeddingReranker(vectorProvider: { _ in nil })
        XCTAssertEqual(unavailable.rerank(question: "question", candidates: [first, second]), [first, second])
        let missingCandidate = SentenceEmbeddingReranker(vectorProvider: { text in text == "question" ? [1] : nil })
        XCTAssertEqual(missingCandidate.rerank(question: "question", candidates: [first, second]), [first, second])
    }

    func testEngineSkipsRerankingForClosingSoon() async throws {
        let source = FakeGrantsDataSource(responses: [
            .response([sample(title: "First"), sample(title: "Second")], total: 2)
        ])
        let answer = try await AskEngine(
            dataSource: source,
            locale: locale,
            reranker: ReverseReranker()
        ).answer("closing soon")

        XCTAssertEqual(answer.citations.first?.opportunity.opportunityTitle, "First")
        XCTAssertCitationInvariant(answer)
    }

    func testGoldenTextRuralClinicScenario() async throws {
        let posted = sample(
            title: "Rural Health Clinic Grant",
            code: "HHS-HRSA",
            status: .posted,
            summary: OpportunitySummary(
                closeDate: "2026-12-12",
                awardCeiling: 1_000_000,
                applicantTypes: ["nonprofits_non_higher_education_with_501c3", "county_governments"],
                fundingCategories: ["health", "agriculture"]
            )
        )
        let earlier = sample(
            title: "Community Clinic Renewal",
            code: "HHS-HRSA",
            status: .posted,
            summary: OpportunitySummary(closeDate: "2026-10-30")
        )
        let forecast = sample(
            title: "Rural Care Forecast",
            code: "HHS-HRSA",
            status: .forecasted,
            summary: OpportunitySummary(forecastedPostDate: "2027-03-01")
        )
        let source = FakeGrantsDataSource(responses: [.response([posted, earlier, forecast], total: 3)])
        let answer = try await engine(source).answer("rural health clinic")
        XCTAssertCitationInvariant(answer)

        XCTAssertEqual(render(answer), """
        The closest match is HRSA's Rural Health Clinic Grant [1]. It's open to nonprofits and county governments and is listed under health and agriculture, with awards up to $1,000,000. Applications close December 12, 2026. [1]

        HRSA's Community Clinic Renewal [2] closes sooner, on October 30. [2] HRSA's Rural Care Forecast [3] is forecasted to open March 2027. [3]
        """)
    }

    func testGoldenTextSparseAndLargerAwards() async throws {
        let sparse = sample(title: "Sparse match", code: "EPA", summary: OpportunitySummary(awardCeiling: 1_000_000))
        let larger = sample(
            title: "Larger award",
            code: "HHS",
            summary: OpportunitySummary(awardCeiling: 2_000_000)
        )
        let source = FakeGrantsDataSource(responses: [.response([sparse, larger], total: 2)])
        let answer = try await engine(source).answer("housing")
        XCTAssertCitationInvariant(answer)

        XCTAssertEqual(render(answer), """
        The closest match is EPA's Sparse match [1]. Awards go up to $1,000,000. [1]

        HHS's Larger award [2] offers larger awards, up to $2,000,000. [2]
        """)
    }

    func testGoldenTextClosingSoonResearch() async throws {
        let listing = sample(
            title: "Research Award",
            code: "NOAA",
            status: .posted,
            summary: OpportunitySummary(
                closeDate: "2027-05-09",
                awardCeiling: 400_000,
                fundingCategories: ["science_technology_and_other_research_and_development"]
            )
        )
        let source = FakeGrantsDataSource(responses: [.response([listing], total: 1)])
        let answer = try await engine(source).answer("closing soon research")
        XCTAssertCitationInvariant(answer)

        XCTAssertEqual(render(answer), """
        The closest match is NOAA's Research Award [1]. It's listed under science and technology research, with awards up to $400,000. Applications close May 9, 2027. [1]
        """)
    }

    func testWritePreviewAnswerArtifactWhenRequested() async throws {
        guard let artifactPath = ProcessInfo.processInfo.environment["SGASK_GOLDEN_ARTIFACT"] else { return }
        let prompts = [
            "Grants for a rural health clinic",
            "Arts funding for a small nonprofit",
            "Climate resilience projects for my city",
            "Research funding for early-career scientists"
        ]
        let preview = PreviewDataSource()
        var sections = ["# PreviewDataSource answers"]
        for prompt in prompts {
            let answer = try await AskEngine(dataSource: preview, locale: locale, reranker: nil).answer(prompt)
            let answerText = render(answer)
            let result = answerText.isEmpty
                ? "_No matches in PreviewDataSource (\(answer.totalMatches) total); answer has no paragraphs or citations._"
                : answerText
            sections.append("## \(prompt)\n\n\(result)")
            XCTAssertCitationInvariant(answer)
        }
        let first = sample(
            title: "Artifact rural clinic",
            code: "HHS-HRSA",
            status: .posted,
            summary: OpportunitySummary(closeDate: "2026-12-12", awardCeiling: 1_000_000)
        )
        let sooner = sample(title: "Artifact earlier clinic", code: "HRSA", summary: OpportunitySummary(closeDate: "2026-10-30"))
        let forecast = sample(
            title: "Artifact forecast clinic",
            code: "EPA",
            status: .forecasted,
            summary: OpportunitySummary(forecastedPostDate: "2027-03-01")
        )
        let sparse = sample(title: "Artifact sparse", code: "EPA", summary: OpportunitySummary(awardCeiling: 1_000_000))
        let larger = sample(title: "Artifact larger", code: "HHS", summary: OpportunitySummary(awardCeiling: 2_000_000))
        let closingResearch = sample(
            title: "Artifact research",
            code: "NOAA",
            summary: OpportunitySummary(
                closeDate: "2027-05-09",
                awardCeiling: 400_000,
                fundingCategories: ["science_technology_and_other_research_and_development"]
            )
        )
        let goldenScenarios: [(String, [Opportunity])] = [
            ("Rural clinic", [first, sooner, forecast]),
            ("Sparse top and larger second award", [sparse, larger]),
            ("Closing soon research", [closingResearch])
        ]
        for (title, listings) in goldenScenarios {
            let scripted = FakeGrantsDataSource(responses: [.response(listings, total: listings.count)])
            let answer = try await engine(scripted).answer(title == "Closing soon research" ? "closing soon research" : "rural health clinic")
            sections.append("## \(title)\n\n\(render(answer))")
        }
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: artifactPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sections.joined(separator: "\n\n").write(toFile: artifactPath, atomically: true, encoding: .utf8)
    }

    private func engine(_ source: FakeGrantsDataSource) -> AskEngine {
        AskEngine(dataSource: source, locale: locale, reranker: nil)
    }

    private func render(_ answer: AskAnswer) -> String {
        answer.paragraphs.map { paragraph in
            paragraph.segments.map { segment in
                segment.text + (segment.citationIndex.map { " [\($0)]" } ?? "")
            }.joined()
        }.joined(separator: "\n\n")
    }

    private func XCTAssertCitationInvariant(
        _ answer: AskAnswer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedIndices = answer.citations.isEmpty ? [] : Array(1...answer.citations.count)
        XCTAssertEqual(answer.citations.map(\.index), expectedIndices, file: file, line: line)
        for paragraph in answer.paragraphs {
            XCTAssertTrue(paragraph.segments.contains { $0.citationIndex != nil }, file: file, line: line)
            for segment in paragraph.segments {
                if segment.citationIndex == nil {
                    XCTAssertFalse(segment.text.contains("HRSA"), file: file, line: line)
                    XCTAssertFalse(segment.text.contains("NOAA"), file: file, line: line)
                    XCTAssertFalse(segment.text.contains("1,000,000"), file: file, line: line)
                }
                if let emphasizedText = segment.emphasizedText {
                    XCTAssertTrue(segment.text.contains(emphasizedText), file: file, line: line)
                    XCTAssertNotNil(segment.citationIndex, file: file, line: line)
                }
            }
        }
        if answer.citations.isEmpty {
            XCTAssertTrue(answer.paragraphs.isEmpty, file: file, line: line)
        }
    }

    private func sample(
        title: String?,
        number: String? = "DEMO-100",
        code: String? = nil,
        status: OpportunityStatus = .posted,
        summary: OpportunitySummary = OpportunitySummary()
    ) -> Opportunity {
        Opportunity(
            opportunityId: UUID().uuidString,
            opportunityNumber: number,
            opportunityTitle: title,
            agencyCode: code,
            opportunityStatus: status,
            summary: summary
        )
    }
}

private struct ReverseReranker: AskReranking {
    func rerank(question: String, candidates: [Opportunity]) -> [Opportunity] {
        Array(candidates.reversed())
    }
}

private actor FakeGrantsDataSource: GrantsDataSource {
    enum ScriptedResponse: Sendable {
        case noResults
        case results([Opportunity], total: Int?)

        func value() -> SearchResponse {
            switch self {
            case .noResults:
                SearchResponse(data: [], paginationInfo: PaginationInfo(totalRecords: 0), facetCounts: [:])
            case let .results(data, total):
                SearchResponse(data: data, paginationInfo: PaginationInfo(totalRecords: total), facetCounts: [:])
            }
        }
    }

    private let responses: [ScriptedResponse]
    private var requestLog: [SearchRequest] = []
    private var callIndex = 0

    init(responses: [ScriptedResponse]) {
        self.responses = responses
    }

    func recordedRequests() -> [SearchRequest] { requestLog }

    func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        requestLog.append(request)
        defer { callIndex += 1 }
        return responses.indices.contains(callIndex) ? responses[callIndex].value() : ScriptedResponse.noResults.value()
    }

    func opportunity(id: String) async throws -> OpportunityDetail { throw GrantsError.notFound }
    func currentUser() async throws -> UserProfile { throw GrantsError.notFound }
    func organizations() async throws -> [Organization] { throw GrantsError.notFound }
    func applications() async throws -> [ApplicationSummary] { throw GrantsError.notFound }
    func startApplication(competitionId: String, name: String, organizationId: String?) async throws -> String {
        throw GrantsError.notFound
    }
    func application(id: String) async throws -> Application { throw GrantsError.notFound }
    func form(id: String) async throws -> FormDefinition { throw GrantsError.notFound }
    func saveForm(applicationId: String, formId: String, response: JSONValue) async throws -> FormSaveResult {
        throw GrantsError.notFound
    }
    func submit(applicationId: String) async throws -> SubmissionResult { throw GrantsError.notFound }
    func savedOpportunityIds() async throws -> Set<String> { throw GrantsError.notFound }
    func setSaved(_ saved: Bool, opportunityId: String) async throws { throw GrantsError.notFound }
}

private extension FakeGrantsDataSource.ScriptedResponse {
    static var empty: Self { .noResults }
    static func response(_ data: [Opportunity], total: Int? = nil) -> Self { .results(data, total: total) }
}
