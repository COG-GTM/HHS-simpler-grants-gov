import Foundation
import SGModels
import XCTest
@testable import SGSampleData

final class SampleDataSourceTests: XCTestCase {
    private let anchorDate = "2026-10-06"

    func testCuratedResourcesDecodeAndCoverDesignListings() async throws {
        let source = try makeSource(anchorDate)
        let response = try await source.searchOpportunities(
            SearchRequest(pagination: SearchPagination(pageSize: 100))
        )
        let opportunities = response.data

        XCTAssertGreaterThanOrEqual(opportunities.count, 28)
        XCTAssertEqual(Set(opportunities.map(\.opportunityId)).count, opportunities.count)
        XCTAssertEqual(Set(opportunities.compactMap(\.opportunityNumber)).count, opportunities.count)
        XCTAssertEqual(Set(opportunities.map(\.opportunityStatus.rawValue)), Set(["posted", "forecasted", "closed", "archived"]))
        XCTAssertEqual(response.paginationInfo.totalRecords, opportunities.count)

        let expectedAgencies = [
            "HHS-HRSA", "HHS-SAMHSA", "HHS-CDC", "USDA-RD", "NSF", "NEA", "NEH",
            "EPA", "DOE-SC", "ED", "DOT-FHWA", "HUD", "USDOJ-OJP-BJA", "DOC-EDA"
        ]
        for agency in expectedAgencies {
            XCTAssertTrue(opportunities.contains(where: { $0.agencyCode == agency }), "Missing agency \(agency)")
        }

        for opportunity in opportunities {
            let detail = try await source.opportunity(id: opportunity.opportunityId)
            XCTAssertFalse(detail.summary.summaryDescription?.isEmpty ?? true)
            XCTAssertFalse(detail.summary.applicantEligibilityDescription?.isEmpty ?? true)
            XCTAssertTrue(detail.summary.agencyContactDescription?.contains("@sample.grants.example") ?? false)
            XCTAssertTrue((1...3).contains(detail.attachments.count))
            XCTAssertTrue(detail.attachments.allSatisfy { $0.downloadPath?.hasPrefix("https://sample.grants.example/") == true })
        }

        let closingSoon = opportunities.filter { opportunity in
            guard opportunity.opportunityStatus == .posted,
                  let close = parseDate(opportunity.summary.closeDate),
                  let today = parseDate(anchorDate)
            else { return false }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            let days = calendar.dateComponents([.day], from: today, to: close).day ?? Int.max
            return (0...14).contains(days)
        }
        XCTAssertGreaterThanOrEqual(closingSoon.count, 3)

        let hrsa = try await source.opportunity(id: "hrsa-27-014")
        XCTAssertEqual(hrsa.opportunityNumber, "HRSA-27-014")
        XCTAssertEqual(hrsa.opportunityStatus, .posted)
        XCTAssertEqual(hrsa.summary.closeDate, "2026-12-12")
        XCTAssertEqual(hrsa.summary.awardFloor, 500_000)
        XCTAssertEqual(hrsa.summary.awardCeiling, 1_000_000)
        XCTAssertEqual(hrsa.summary.expectedNumberOfAwards, 60)
        XCTAssertEqual(hrsa.summary.estimatedTotalProgramFunding, 60_000_000)
        XCTAssertEqual(hrsa.competitions.first?.competitionForms.map(\.form.formId), [
            "1623b310-85be-496a-b84b-34bdee22a68a",
            "08e6603f-d197-4a60-98cd-d49acb1fc1fd",
            "1d0681f8-26f9-4ff1-a75e-e33477668f73",
            "32165da2-354d-42c0-a986-cf4f2f350039",
            "6ebd786f-cccf-4ee1-a100-61436975025b",
            "778a1485-082a-463e-a61b-6615ccebe027"
        ])
        XCTAssertEqual(hrsa.competitions.first?.competitionForms.map(\.isRequired), [true, true, true, true, true, false])
        let usda = try await source.opportunity(id: "usda-rd-27-05")
        let nsf = try await source.opportunity(id: "nsf-27-512")
        let epa = try await source.opportunity(id: "epa-r-27-03")
        let nea = try await source.opportunity(id: "nea-27-02")
        XCTAssertEqual(usda.summary.closeDate, "2026-10-30")
        XCTAssertEqual(nsf.opportunityStatus, .forecasted)
        XCTAssertTrue(epa.opportunityTitle?.contains("Environmental Justice") == true)
        XCTAssertTrue(nea.opportunityTitle?.contains("Arts Projects") == true)
        XCTAssertTrue(opportunities.contains(where: { $0.opportunityId != "hrsa-27-014" && $0.opportunityStatus == .posted }))
        do {
            _ = try await source.opportunity(id: "missing")
            XCTFail("Expected missing opportunity to fail")
        } catch GrantsError.notFound {}
    }

    func testDatesShiftRelativeToTheReferenceDay() async throws {
        let anchor = try makeSource("2026-10-06")
        let shifted = try makeSource("2027-06-01")
        let atAnchor = try await anchor.searchOpportunities(SearchRequest(pagination: SearchPagination(pageSize: 100)))
        let atShiftedDate = try await shifted.searchOpportunities(SearchRequest(pagination: SearchPagination(pageSize: 100)))
        let anchorStatuses = Dictionary(uniqueKeysWithValues: atAnchor.data.map { ($0.opportunityId, $0.opportunityStatus) })

        XCTAssertTrue(atShiftedDate.data.allSatisfy { anchorStatuses[$0.opportunityId] == $0.opportunityStatus })
        let hrsa = try await shifted.opportunity(id: "hrsa-27-014")
        XCTAssertEqual(hrsa.summary.closeDate, "2027-08-07")
        XCTAssertEqual(daysBetween("2027-06-01", "2027-08-07"), 67)
        for item in atShiftedDate.data where item.opportunityStatus == .posted {
            XCTAssertGreaterThanOrEqual(item.summary.closeDate ?? "0000-00-00", "2027-06-01")
        }
    }

    func testTryAskingSearchesRankRelevantListingsAndSupportFilters() async throws {
        let source = try makeSource(anchorDate)
        let searches = [
            ("Grants for a rural health clinic", "hrsa-27-020"),
            ("Arts funding for a small nonprofit", "nea-27-04"),
            ("Climate resilience projects for my city", "epa-r-27-14"),
            ("Research funding for early-career scientists", "de-foa-0003012")
        ]
        for (query, expectedID) in searches {
            let result = try await source.searchOpportunities(SearchRequest(query: query, queryOperator: "OR"))
            XCTAssertEqual(result.data.first?.opportunityId, expectedID, "Unexpected first match for \(query)")
        }

        let and = try await source.searchOpportunities(SearchRequest(query: "rural opioid"))
        let or = try await source.searchOpportunities(SearchRequest(query: "rural opioid", queryOperator: "OR"))
        XCTAssertEqual(and.data.first?.opportunityId, "hrsa-27-014")
        XCTAssertLessThan(and.data.count, or.data.count)
        let caseInsensitive = try await source.searchOpportunities(SearchRequest(query: "RURAL OPIOID"))
        XCTAssertEqual(caseInsensitive.data.first?.opportunityId, "hrsa-27-014")

        let status = try await source.searchOpportunities(SearchRequest(filters: SearchFilters(opportunityStatus: ["forecasted"])))
        XCTAssertTrue(status.data.allSatisfy { $0.opportunityStatus == .forecasted })
        let applicant = try await source.searchOpportunities(SearchRequest(filters: SearchFilters(applicantType: ["public_and_state_institutions_of_higher_education"])))
        XCTAssertTrue(applicant.data.allSatisfy { $0.summary.applicantTypes?.contains("public_and_state_institutions_of_higher_education") == true })
        let category = try await source.searchOpportunities(SearchRequest(filters: SearchFilters(fundingCategory: ["health"])))
        XCTAssertTrue(category.data.allSatisfy { $0.summary.fundingCategories?.contains("health") == true })
        let instrument = try await source.searchOpportunities(SearchRequest(filters: SearchFilters(fundingInstrument: ["cooperative_agreement"])))
        XCTAssertTrue(instrument.data.allSatisfy { $0.summary.fundingInstruments?.contains("cooperative_agreement") == true })
        let agency = try await source.searchOpportunities(SearchRequest(filters: SearchFilters(agency: ["EPA"])))
        XCTAssertTrue(agency.data.allSatisfy { $0.agencyCode == "EPA" })
        let agencyPrefix = try await source.searchOpportunities(SearchRequest(filters: SearchFilters(agency: ["HHS"])))
        XCTAssertTrue(agencyPrefix.data.allSatisfy { $0.agencyCode?.hasPrefix("HHS-") == true })
    }

    func testSortOrdersPaginationAndFacets() async throws {
        let source = try makeSource(anchorDate)
        for order in ["close_date", "post_date", "award_ceiling", "opportunity_title", "opportunity_number", "agency_code"] {
            for direction in ["ascending", "descending"] {
                let result = try await source.searchOpportunities(
                    SearchRequest(pagination: SearchPagination(
                        pageSize: 100,
                        sortOrder: [SortOrder(orderBy: order, sortDirection: direction)]
                    ))
                )
                XCTAssertTrue(zip(result.data, result.data.dropFirst()).allSatisfy {
                    isOrdered($0, $1, by: order, direction: direction)
                }, "Incorrect \(direction) sort for \(order)")
            }
        }
        let relevancy = try await source.searchOpportunities(
            SearchRequest(query: "rural opioid", pagination: SearchPagination(
                pageSize: 100,
                sortOrder: [SortOrder(orderBy: "relevancy", sortDirection: "descending")]
            ))
        )
        XCTAssertEqual(relevancy.data.first?.opportunityId, "hrsa-27-014")
        let relevancyAscending = try await source.searchOpportunities(
            SearchRequest(query: "rural opioid", pagination: SearchPagination(
                pageSize: 100,
                sortOrder: [SortOrder(orderBy: "relevancy", sortDirection: "ascending")]
            ))
        )
        XCTAssertEqual(relevancyAscending.data.last?.opportunityId, "hrsa-27-014")

        let first = try await source.searchOpportunities(SearchRequest(pagination: SearchPagination(pageSize: 7)))
        let last = try await source.searchOpportunities(SearchRequest(pagination: SearchPagination(pageOffset: 5, pageSize: 7)))
        let beyond = try await source.searchOpportunities(SearchRequest(pagination: SearchPagination(pageOffset: 6, pageSize: 7)))
        XCTAssertEqual(first.paginationInfo.totalPages, 5)
        XCTAssertEqual(last.data.count, 4)
        XCTAssertTrue(beyond.data.isEmpty)
        XCTAssertEqual(beyond.paginationInfo.totalRecords, 32)
        XCTAssertEqual(first.facetCounts["opportunity_status"]?.values.reduce(0, +), first.paginationInfo.totalRecords)
        XCTAssertLessThanOrEqual(first.facetCounts["close_date"]?["7"] ?? 0, first.facetCounts["close_date"]?["30"] ?? 0)
        XCTAssertEqual(first.facetCounts["agency"]?["HHS-HRSA"], 4)
        let filtered = try await source.searchOpportunities(SearchRequest(
            query: "rural",
            queryOperator: "OR",
            filters: SearchFilters(opportunityStatus: ["posted"])
        ))
        XCTAssertEqual(filtered.facetCounts["opportunity_status"]?.keys.sorted(), ["posted"])
    }

    func testFormsAndOpportunityDetailsLoadFromResources() async throws {
        let source = try makeSource(anchorDate)
        let ids = [
            "1623b310-85be-496a-b84b-34bdee22a68a",
            "08e6603f-d197-4a60-98cd-d49acb1fc1fd",
            "1d0681f8-26f9-4ff1-a75e-e33477668f73",
            "32165da2-354d-42c0-a986-cf4f2f350039",
            "778a1485-082a-463e-a61b-6615ccebe027",
            "6ebd786f-cccf-4ee1-a100-61436975025b"
        ]
        for id in ids {
            let form = try await source.form(id: id)
            XCTAssertFalse(form.formJsonSchema["properties"] == nil)
            XCTAssertFalse(form.formUiSchema == .array([]))
            XCTAssertFalse(containsReference(form.formJsonSchema))
        }
        let epa = try await source.opportunity(id: "epa-r-27-03")
        XCTAssertFalse(epa.attachments.isEmpty)
        XCTAssertTrue(epa.competitions.contains(where: { !$0.isSimplerGrantsEnabled }))
        do {
            _ = try await source.opportunity(id: "not-a-grant")
            XCTFail("Expected missing opportunity to fail")
        } catch GrantsError.notFound {}
    }

    func testRequiredFieldValidatorHandlesNestedArraysConditionalsAndEmptyStrings() {
        let nestedSchema: JSONValue = .object([
            "properties": .object(["contact": .object([
                "type": .string("object"),
                "required": .array([.string("email")]),
                "properties": .object(["email": .object(["type": .string("string")])])
            ])])
        ])
        let nestedWarnings = RequiredFieldValidator.validate(
            schema: nestedSchema,
            response: .object(["contact": .object([:])])
        )
        XCTAssertEqual(nestedWarnings.map(\.field), ["$.contact.email"])

        let arraySchema: JSONValue = .object([
            "properties": .object(["sites": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "required": .array([.string("address")]),
                    "properties": .object(["address": .object(["type": .string("string")])])
                ])
            ])])
        ])
        let arrayWarnings = RequiredFieldValidator.validate(
            schema: arraySchema,
            response: .object(["sites": .array([.object([:])])])
        )
        XCTAssertEqual(arrayWarnings.map(\.field), ["$.sites.0.address"])

        let conditionalSchema: JSONValue = .object([
            "if": .object([
                "properties": .object(["application_type": .object(["const": .string("Revision")])]),
                "required": .array([.string("application_type")])
            ]),
            "then": .object(["required": .array([.string("federal_award_identifier")])])
        ])
        let conditionalWarnings = RequiredFieldValidator.validate(
            schema: conditionalSchema,
            response: .object(["application_type": .string("Revision")])
        )
        XCTAssertEqual(conditionalWarnings.map(\.field), ["$.federal_award_identifier"])
        let anyOfSchema: JSONValue = .object([
            "if": .object(["anyOf": .array([
                .object(["properties": .object(["application_type": .object(["enum": .array([.string("Revision")])])])]),
                .object(["properties": .object(["application_type": .object(["const": .string("Continuation")])])])
            ])]),
            "then": .object(["required": .array([.string("federal_award_identifier")])])
        ])
        let anyOfWarnings = RequiredFieldValidator.validate(
            schema: anyOfSchema,
            response: .object(["application_type": .string("Revision")])
        )
        XCTAssertEqual(anyOfWarnings.map(\.field), ["$.federal_award_identifier"])
        let emptyWarnings = RequiredFieldValidator.validate(
            schema: nestedSchema,
            response: .object(["contact": .object(["email": .string("")])])
        )
        XCTAssertEqual(emptyWarnings.first?.field, "$.contact.email")
    }

    func testApplicationLifecycleAndPrefill() async throws {
        let source = try makeSource(anchorDate)
        let organizations = try await source.organizations()
        let organization = try XCTUnwrap(organizations.first)
        let applicationID = try await source.startApplication(
            competitionId: "usda-rd-27-05-open",
            name: "Sample Community Facilities Plan",
            organizationId: organization.organizationId
        )
        let initial = try await source.application(id: applicationID)
        let sf424 = try XCTUnwrap(initial.applicationForms.first(where: { $0.formId == "1623b310-85be-496a-b84b-34bdee22a68a" }))
        XCTAssertEqual(sf424.applicationResponse["funding_opportunity_number"], .string("USDA-RD-27-05"))
        XCTAssertEqual(sf424.applicationResponse["organization_name"], .string("Bluefield Community Health Center"))

        let partial = try await source.saveForm(
            applicationId: applicationID,
            formId: sf424.formId,
            response: .object([:])
        )
        XCTAssertFalse(partial.warnings.isEmpty)
        XCTAssertEqual(partial.form.applicationFormStatus, "in_progress")
        do {
            _ = try await source.submit(applicationId: applicationID)
            XCTFail("Expected incomplete application submission to fail")
        } catch GrantsError.server(status: 422, _) {}
        let afterRejectedSubmission = try await source.application(id: applicationID)
        XCTAssertEqual(afterRejectedSubmission.applicationStatus, "in_progress")

        for form in initial.applicationForms {
            let definition = try await source.form(id: form.formId)
            let complete = RequiredFieldValidator.minimalInstance(schema: definition.formJsonSchema)
            let result = try await source.saveForm(applicationId: applicationID, formId: form.formId, response: complete)
            XCTAssertTrue(result.warnings.isEmpty, "Generated response did not satisfy \(form.formId)")
        }
        let submitted = try await source.submit(applicationId: applicationID)
        XCTAssertEqual(submitted.trackingNumber, "GRANT14102837")
        XCTAssertTrue(submitted.trackingNumber?.range(of: "^GRANT\\d{8}$", options: .regularExpression) != nil)
        let submittedApplication = try await source.application(id: applicationID)
        let applications = try await source.applications()
        XCTAssertEqual(submittedApplication.applicationStatus, "submitted")
        XCTAssertTrue(applications.contains(where: { $0.applicationId == applicationID }))

        do {
            _ = try await source.startApplication(
                competitionId: "epa-r-27-03-open",
                name: "External Application",
                organizationId: organization.organizationId
            )
            XCTFail("Expected non-Simpler competition to be rejected")
        } catch GrantsError.server(status: 422, _) {}
        do {
            _ = try await source.startApplication(
                competitionId: "hrsa-26-099-closed",
                name: "Closed Sample Application",
                organizationId: organization.organizationId
            )
            XCTFail("Expected closed competition to be rejected")
        } catch GrantsError.server(status: 422, _) {}
    }

    func testSeededApplicationAndSavedOpportunityToggles() async throws {
        let source = try makeSource(anchorDate)
        let seeded = try await source.application(id: "sample-application-0001")
        XCTAssertEqual(seeded.applicationForms.count, 6)
        XCTAssertEqual(seeded.applicationForms.filter { $0.applicationFormStatus == "complete" }.count, 3)
        XCTAssertEqual(seeded.applicationForms.map(\.form.formName), [
            "Application for Federal Assistance (SF-424)",
            "Budget Information for Non-Construction Programs (SF-424A)",
            "Assurances for Non-Construction Programs (SF-424B)",
            "Project Narrative Attachment Form",
            "PROJECT/PERFORMANCE SITE LOCATION(S)",
            "Disclosure of Lobbying Activities (SF-LLL)"
        ])
        for form in seeded.applicationForms where form.applicationFormStatus == "complete" {
            XCTAssertTrue(RequiredFieldValidator.validate(
                schema: form.form.formJsonSchema,
                response: form.applicationResponse
            ).isEmpty)
        }
        var saved = try await source.savedOpportunityIds()
        XCTAssertTrue(saved.contains("hrsa-27-014"))
        XCTAssertTrue(saved.contains("nea-27-02"))
        try await source.setSaved(true, opportunityId: "usda-rd-27-05")
        saved = try await source.savedOpportunityIds()
        XCTAssertTrue(saved.contains("usda-rd-27-05"))
        try await source.setSaved(false, opportunityId: "nea-27-02")
        saved = try await source.savedOpportunityIds()
        XCTAssertFalse(saved.contains("nea-27-02"))
    }

    func testProfileOrganizationAndAuthenticatorShareSampleIdentity() async throws {
        let source = try makeSource(anchorDate)
        let user = try await source.currentUser()
        XCTAssertEqual(user.userId, "sample-dana-reyes")
        XCTAssertEqual(user.email, "dana.reyes@bluefieldchc.example")
        let organizations = try await source.organizations()
        let organization = try XCTUnwrap(organizations.first)
        XCTAssertEqual(organization.samGovEntity?.uei, "K7LMN2QX4R91")
        XCTAssertEqual(organization.samGovEntity?.expirationDate, "2027-06-06")

        let auth = SampleAuthenticator()
        let initialRestore = await auth.restore()
        XCTAssertNil(initialRestore)
        let signedIn = try await auth.signIn(pivRequired: false)
        XCTAssertEqual(signedIn, user)
        let restored = await auth.restore()
        XCTAssertEqual(restored, user)
        await auth.signOut()
        let afterSignOut = await auth.restore()
        XCTAssertNil(afterSignOut)
        let pivAuth = SampleAuthenticator(normalSignInDelay: .zero, pivSignInDelay: .zero)
        let pivUser = try await pivAuth.signIn(pivRequired: true)
        XCTAssertEqual(pivUser, user)
    }

    private func makeSource(_ date: String) throws -> SampleDataSource {
        SampleDataSource(referenceDate: try XCTUnwrap(parseDate(date)), latency: .zero)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func daysBetween(_ start: String, _ end: String) -> Int? {
        guard let startDate = parseDate(start), let endDate = parseDate(end) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.dateComponents([.day], from: startDate, to: endDate).day
    }

    private func containsReference(_ value: JSONValue) -> Bool {
        switch value {
        case let .object(values):
            values.contains { $0.key == "$ref" || containsReference($0.value) }
        case let .array(values):
            values.contains(where: containsReference)
        default:
            false
        }
    }

    private func isOrdered(_ lhs: Opportunity, _ rhs: Opportunity, by order: String, direction: String) -> Bool {
        let ascending = direction == "ascending"
        if order == "award_ceiling" {
            return ordered(lhs.summary.awardCeiling, rhs.summary.awardCeiling, ascending: ascending)
        }
        if order == "close_date" {
            return ordered(lhs.summary.closeDate, rhs.summary.closeDate, ascending: ascending)
        }
        if order == "post_date" {
            return ordered(lhs.summary.postDate, rhs.summary.postDate, ascending: ascending)
        }
        if order == "opportunity_title" {
            return ordered(lhs.opportunityTitle, rhs.opportunityTitle, ascending: ascending)
        }
        if order == "opportunity_number" {
            return ordered(lhs.opportunityNumber, rhs.opportunityNumber, ascending: ascending)
        }
        return ordered(lhs.agencyCode, rhs.agencyCode, ascending: ascending)
    }

    private func ordered<T: Comparable>(_ lhs: T?, _ rhs: T?, ascending: Bool) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?):
            return left == right || (ascending ? left < right : left > right)
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return true
        }
    }
}
