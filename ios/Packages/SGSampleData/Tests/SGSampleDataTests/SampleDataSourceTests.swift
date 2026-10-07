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

        var attachmentCounts = Set<Int>()
        var nonSimplerPostedCompetitionIDs = Set<String>()
        let requiredFormIDs: Set<String> = [
            "1623b310-85be-496a-b84b-34bdee22a68a",
            "08e6603f-d197-4a60-98cd-d49acb1fc1fd",
            "1d0681f8-26f9-4ff1-a75e-e33477668f73",
            "32165da2-354d-42c0-a986-cf4f2f350039"
        ]
        for opportunity in opportunities {
            let detail = try await source.opportunity(id: opportunity.opportunityId)
            XCTAssertFalse(detail.summary.summaryDescription?.isEmpty ?? true)
            XCTAssertFalse(detail.summary.applicantEligibilityDescription?.isEmpty ?? true)
            XCTAssertTrue(detail.summary.agencyContactDescription?.contains("@sample.grants.example") ?? false)
            XCTAssertTrue((1...3).contains(detail.attachments.count))
            attachmentCounts.insert(detail.attachments.count)
            XCTAssertTrue(detail.attachments.allSatisfy { $0.downloadPath?.hasPrefix("https://sample.grants.example/") == true })
            for competition in detail.competitions {
                let applicants = Set(competition.openToApplicants)
                XCTAssertTrue(applicants.isSubset(of: ["organization", "individual"]))
                let expectedApplicants = detail.opportunityId == "neh-27-011"
                    ? ["individual", "organization"]
                    : ["organization"]
                XCTAssertEqual(competition.openToApplicants, expectedApplicants)
            }
            switch detail.opportunityStatus {
            case .posted:
                XCTAssertTrue(detail.competitions.contains(where: \.isOpen), "Posted listing \(detail.opportunityId) has no open competition")
                for competition in detail.competitions where competition.isOpen {
                    if !competition.isSimplerGrantsEnabled {
                        nonSimplerPostedCompetitionIDs.insert(competition.competitionId)
                    } else {
                        XCTAssertTrue((4...6).contains(competition.competitionForms.count))
                        let required = Set(competition.competitionForms.filter(\.isRequired).map(\.form.formId))
                        XCTAssertTrue(requiredFormIDs.isSubset(of: required), "Missing required forms for \(detail.opportunityId)")
                    }
                }
            case .forecasted:
                XCTAssertTrue(detail.competitions.isEmpty, "Forecasted listing \(detail.opportunityId) should not have a competition")
            case .closed, .archived:
                XCTAssertFalse(detail.competitions.isEmpty, "Closed listing \(detail.opportunityId) should have a competition")
                XCTAssertTrue(detail.competitions.allSatisfy { !$0.isOpen })
            }
        }
        XCTAssertTrue(attachmentCounts.contains(2))
        XCTAssertTrue(attachmentCounts.contains(3))
        XCTAssertEqual(nonSimplerPostedCompetitionIDs, ["epa-r-27-03-open", "dot-fhwa-27-004-open"])

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
            "32165da2-354d-42c0-a986-cf4f2f350039",
            "1d0681f8-26f9-4ff1-a75e-e33477668f73",
            "6ebd786f-cccf-4ee1-a100-61436975025b",
            "778a1485-082a-463e-a61b-6615ccebe027"
        ])
        XCTAssertEqual(hrsa.competitions.first?.competitionForms.map(\.isRequired), [true, true, true, true, true, true])
        XCTAssertTrue(hrsa.attachments.contains {
            $0.fileName?.hasSuffix(".xlsx") == true
                && $0.mimeType == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        })
        let usda = try await source.opportunity(id: "usda-rd-27-05")
        let nsf = try await source.opportunity(id: "nsf-27-512")
        let epa = try await source.opportunity(id: "epa-r-27-03")
        let nea = try await source.opportunity(id: "nea-27-02")
        XCTAssertEqual(usda.summary.closeDate, "2026-10-30")
        XCTAssertEqual(nsf.opportunityStatus, .forecasted)
        XCTAssertTrue(nsf.attachments.contains {
            $0.fileName?.hasSuffix(".docx") == true
                && $0.mimeType == "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        })
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
        let scriptedAsk = try await source.searchOpportunities(SearchRequest(
            query: "We run a rural clinic and want to expand addiction treatment",
            queryOperator: "OR"
        ))
        let scriptedTopFive = Array(scriptedAsk.data.prefix(5)).map(\.opportunityId)
        XCTAssertEqual(scriptedTopFive.first, "hrsa-27-014")
        XCTAssertTrue(scriptedTopFive.contains("usda-rd-27-05"), "Expected USDA in top five, got \(scriptedTopFive)")
        XCTAssertTrue(scriptedTopFive.contains("nsf-27-512"), "Expected NSF in top five, got \(scriptedTopFive)")

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

        let minItemsSchema: JSONValue = .object([
            "required": .array([.string("entries")]),
            "properties": .object(["entries": .object([
                "type": .string("array"),
                "minItems": .number(2),
                "items": .object([
                    "type": .string("object"),
                    "required": .array([.string("name")]),
                    "properties": .object(["name": .object(["type": .string("string")])])
                ])
            ])])
        ])
        let shortArrayWarnings = RequiredFieldValidator.validate(
            schema: minItemsSchema,
            response: .object(["entries": .array([])])
        )
        XCTAssertEqual(shortArrayWarnings.map(\.field), ["$.entries"])
        XCTAssertEqual(shortArrayWarnings.map(\.message), ["Expected at least 2 items"])
        XCTAssertEqual(shortArrayWarnings.map(\.type), ["minItems"])
        let missingArrayWarnings = RequiredFieldValidator.validate(
            schema: minItemsSchema,
            response: .object([:])
        )
        XCTAssertEqual(missingArrayWarnings.map(\.type), ["required"])
        let generated = RequiredFieldValidator.minimalInstance(schema: minItemsSchema)
        guard case let .object(generatedValues) = generated,
              case let .array(entries)? = generatedValues["entries"]
        else {
            XCTFail("Expected generated entries array")
            return
        }
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0["name"] != nil })
    }

    func testSF424OtherApplicantWarningMatchesOnlyOtherApplicantCode() async throws {
        let source = try makeSource(anchorDate)
        let definition = try await source.form(id: "1623b310-85be-496a-b84b-34bdee22a68a")

        let regionalWarnings = RequiredFieldValidator.validate(
            schema: definition.formJsonSchema,
            response: .object([
                "applicant_type_code": .array([.string("E: Regional Organization")])
            ])
        )
        XCTAssertFalse(regionalWarnings.contains { $0.field == "$.applicant_type_other_specify" })

        let otherWarnings = RequiredFieldValidator.validate(
            schema: definition.formJsonSchema,
            response: .object([
                "applicant_type_code": .array([.string("X: Other (specify)")])
            ])
        )
        XCTAssertTrue(otherWarnings.contains { $0.field == "$.applicant_type_other_specify" })
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

    func testSaveSF424PopulatesTotalEstimatedFunding() async throws {
        let source = try makeSource(anchorDate)
        let organizations = try await source.organizations()
        let organization = try XCTUnwrap(organizations.first)
        let applicationID = try await source.startApplication(
            competitionId: "hrsa-27-014-open",
            name: "SF-424 Funding Calculation",
            organizationId: organization.organizationId
        )
        let result = try await source.saveForm(
            applicationId: applicationID,
            formId: "1623b310-85be-496a-b84b-34bdee22a68a",
            response: .object([
                "federal_estimated_funding": .string("540000"),
                "applicant_estimated_funding": .string("0"),
                "state_estimated_funding": .string(""),
                "other_estimated_funding": .string("1,000.50")
            ])
        )

        XCTAssertEqual(result.form.applicationResponse["total_estimated_funding"], .string("541000.50"))
        XCTAssertFalse(result.warnings.contains { $0.field == "$.total_estimated_funding" })
    }

    func testRequiredHRSAFormsCanBeSubmittedWithUIFundingInputs() async throws {
        let source = try makeSource(anchorDate)
        let organizations = try await source.organizations()
        let organization = try XCTUnwrap(organizations.first)
        let applicationID = try await source.startApplication(
            competitionId: "hrsa-27-014-open",
            name: "HRSA Sample Lifecycle",
            organizationId: organization.organizationId
        )
        let application = try await source.application(id: applicationID)
        let requiredForms = application.applicationForms.filter(\.isRequired)
        XCTAssertEqual(requiredForms.count, 6)

        for form in requiredForms {
            var response = RequiredFieldValidator.minimalInstance(schema: form.form.formJsonSchema)
            if form.formId == "1623b310-85be-496a-b84b-34bdee22a68a" {
                guard case var .object(values) = response else {
                    return XCTFail("Expected SF-424 response to be an object")
                }
                values.removeValue(forKey: "total_estimated_funding")
                values.removeValue(forKey: "applicant_type_other_specify")
                values["applicant_type_code"] = .array([.string("E: Regional Organization")])
                values["federal_estimated_funding"] = .string("540000")
                values["applicant_estimated_funding"] = .string("0")
                values["state_estimated_funding"] = .string("0")
                values["local_estimated_funding"] = .string("0")
                values["other_estimated_funding"] = .string("0")
                values["program_income_estimated_funding"] = .string("0")
                response = .object(values)
            }

            let result = try await source.saveForm(
                applicationId: applicationID,
                formId: form.formId,
                response: response
            )
            XCTAssertTrue(
                result.warnings.isEmpty,
                "Unexpected warnings for \(form.form.formName ?? form.formId): \(result.warnings.map(\.field))"
            )
            XCTAssertEqual(result.form.applicationFormStatus, "complete")
            if form.formId == "1623b310-85be-496a-b84b-34bdee22a68a" {
                XCTAssertEqual(
                    result.form.applicationResponse["total_estimated_funding"],
                    .string("540000.00")
                )
            }
        }

        let savedApplication = try await source.application(id: applicationID)
        XCTAssertTrue(savedApplication.applicationForms.allSatisfy {
            !$0.isRequired || $0.applicationFormStatus == "complete"
        })
        let submission = try await source.submit(applicationId: applicationID)
        XCTAssertTrue(submission.trackingNumber?.isEmpty == false)
    }

    func testSF424ABudgetRulesPopulateEachActivityLineItemInOrder() async throws {
        let source = try makeSource(anchorDate)
        let organizations = try await source.organizations()
        let organization = try XCTUnwrap(organizations.first)
        let applicationID = try await source.startApplication(
            competitionId: "hrsa-27-014-open",
            name: "SF-424A Activity Line Items",
            organizationId: organization.organizationId
        )
        let result = try await source.saveForm(
            applicationId: applicationID,
            formId: "08e6603f-d197-4a60-98cd-d49acb1fc1fd",
            response: .object([
                "activity_line_items": .array([
                    .object([
                        "budget_categories": .object([
                            "personnel_amount": .string("420000.00"),
                            "travel_amount": .string("1000")
                        ])
                    ]),
                    .object([
                        "budget_categories": .object([
                            "personnel_amount": .string("5")
                        ])
                    ])
                ])
            ])
        )

        let response = result.form.applicationResponse
        XCTAssertEqual(
            response.value(at: ["activity_line_items", "0", "budget_categories", "total_direct_charge_amount"]),
            .string("421000.00")
        )
        XCTAssertEqual(
            response.value(at: ["activity_line_items", "0", "budget_categories", "total_amount"]),
            .string("421000.00")
        )
        XCTAssertEqual(
            response.value(at: ["activity_line_items", "1", "budget_categories", "total_direct_charge_amount"]),
            .string("5.00")
        )
        XCTAssertEqual(
            response.value(at: ["activity_line_items", "1", "budget_categories", "total_amount"]),
            .string("5.00")
        )
        XCTAssertEqual(
            response.value(at: ["total_budget_categories", "personnel_amount"]),
            .string("420005.00")
        )
    }

    func testSF424AForecastRulesPopulateCombinedAndFederalTotals() async throws {
        let source = try makeSource(anchorDate)
        let organizations = try await source.organizations()
        let organization = try XCTUnwrap(organizations.first)
        let applicationID = try await source.startApplication(
            competitionId: "hrsa-27-014-open",
            name: "SF-424A Forecast Totals",
            organizationId: organization.organizationId
        )
        let result = try await source.saveForm(
            applicationId: applicationID,
            formId: "08e6603f-d197-4a60-98cd-d49acb1fc1fd",
            response: .object([
                "forecasted_cash_needs": .object([
                    "federal_forecasted_cash_needs": .object([
                        "first_quarter_amount": .string("100.00")
                    ]),
                    "non_federal_forecasted_cash_needs": .object([
                        "first_quarter_amount": .string("50.00")
                    ])
                ])
            ])
        )

        let response = result.form.applicationResponse
        XCTAssertEqual(
            response.value(at: [
                "forecasted_cash_needs",
                "total_forecasted_cash_needs",
                "first_quarter_amount"
            ]),
            .string("150.00")
        )
        XCTAssertEqual(
            response.value(at: [
                "forecasted_cash_needs",
                "federal_forecasted_cash_needs",
                "total_amount"
            ]),
            .string("100.00")
        )
    }

    func testRepeatSubmitDoesNotAdvanceTrackingNumber() async throws {
        let source = try makeSource(anchorDate)
        let organizations = try await source.organizations()
        let organization = try XCTUnwrap(organizations.first)
        let firstApplicationID = try await source.startApplication(
            competitionId: "usda-rd-27-05-open",
            name: "First Rural Facilities Plan",
            organizationId: organization.organizationId
        )
        try await completeRequiredForms(source, applicationID: firstApplicationID)
        let firstSubmission = try await source.submit(applicationId: firstApplicationID)
        XCTAssertEqual(firstSubmission.trackingNumber, "GRANT14102837")

        do {
            _ = try await source.submit(applicationId: firstApplicationID)
            XCTFail("Expected submitted application to be rejected")
        } catch let error as GrantsError {
            guard case let .server(status, message) = error else { throw error }
            XCTAssertEqual(status, 403)
            XCTAssertEqual(message, "Cannot submit application. It is currently in status: submitted")
        }

        let nextApplicationID = try await source.startApplication(
            competitionId: "usda-rd-27-05-open",
            name: "Second Rural Facilities Plan",
            organizationId: organization.organizationId
        )
        try await completeRequiredForms(source, applicationID: nextApplicationID)
        let nextSubmission = try await source.submit(applicationId: nextApplicationID)
        XCTAssertEqual(nextSubmission.trackingNumber, "GRANT14102838")
    }

    func testOptionalFormsAreIncludedOnlyAfterNonEmptySave() async throws {
        let source = try makeSource(anchorDate)
        let organizations = try await source.organizations()
        let organization = try XCTUnwrap(organizations.first)
        let siteFormID = "6ebd786f-cccf-4ee1-a100-61436975025b"

        let untouchedApplicationID = try await source.startApplication(
            competitionId: "usda-rd-27-05-open",
            name: "Application Without Optional Site",
            organizationId: organization.organizationId
        )
        let untouchedApplication = try await source.application(id: untouchedApplicationID)
        let untouchedSite = try XCTUnwrap(untouchedApplication.applicationForms.first(where: { $0.formId == siteFormID }))
        XCTAssertFalse(untouchedSite.isRequired)
        XCTAssertEqual(untouchedSite.isIncludedInSubmission, false)
        try await completeRequiredForms(source, applicationID: untouchedApplicationID)
        _ = try await source.submit(applicationId: untouchedApplicationID)

        let includedApplicationID = try await source.startApplication(
            competitionId: "usda-rd-27-05-open",
            name: "Application With Optional Site",
            organizationId: organization.organizationId
        )
        let partialSite = try await source.saveForm(
            applicationId: includedApplicationID,
            formId: siteFormID,
            response: .object(["primary_site": .object([:])])
        )
        XCTAssertEqual(partialSite.form.isIncludedInSubmission, true)
        XCTAssertEqual(partialSite.form.applicationFormStatus, "in_progress")
        try await completeRequiredForms(source, applicationID: includedApplicationID)
        do {
            _ = try await source.submit(applicationId: includedApplicationID)
            XCTFail("Expected incomplete included optional form to block submission")
        } catch GrantsError.server(status: 422, _) {}

        let siteDefinition = try await source.form(id: siteFormID)
        let completeSite = RequiredFieldValidator.minimalInstance(schema: siteDefinition.formJsonSchema)
        let savedSite = try await source.saveForm(
            applicationId: includedApplicationID,
            formId: siteFormID,
            response: completeSite
        )
        XCTAssertTrue(savedSite.warnings.isEmpty)
        XCTAssertEqual(savedSite.form.isIncludedInSubmission, true)
        _ = try await source.submit(applicationId: includedApplicationID)

        let clearedApplicationID = try await source.startApplication(
            competitionId: "usda-rd-27-05-open",
            name: "Application With Cleared Optional Site",
            organizationId: organization.organizationId
        )
        let includedClearedSite = try await source.saveForm(
            applicationId: clearedApplicationID,
            formId: siteFormID,
            response: .object(["primary_site": .object([:])])
        )
        XCTAssertEqual(includedClearedSite.form.isIncludedInSubmission, true)
        let clearedSite = try await source.saveForm(
            applicationId: clearedApplicationID,
            formId: siteFormID,
            response: .object([:])
        )
        XCTAssertEqual(clearedSite.form.isIncludedInSubmission, false)
        try await completeRequiredForms(source, applicationID: clearedApplicationID)
        _ = try await source.submit(applicationId: clearedApplicationID)
    }

    func testMinimumArrayCountsKeepFormsInProgress() async throws {
        let source = try makeSource(anchorDate)
        let organizations = try await source.organizations()
        let organization = try XCTUnwrap(organizations.first)
        let applicationID = try await source.startApplication(
            competitionId: "usda-rd-27-05-open",
            name: "Application With Empty Arrays",
            organizationId: organization.organizationId
        )
        let narrativeID = "32165da2-354d-42c0-a986-cf4f2f350039"
        let narrative = try await source.saveForm(
            applicationId: applicationID,
            formId: narrativeID,
            response: .object(["attachments": .array([])])
        )
        XCTAssertTrue(narrative.warnings.contains {
            $0.field == "$.attachments" && $0.message == "[] should be non-empty" && $0.type == "minItems"
        })
        XCTAssertEqual(narrative.form.applicationFormStatus, "in_progress")

        let budgetID = "08e6603f-d197-4a60-98cd-d49acb1fc1fd"
        let budget = try await source.saveForm(
            applicationId: applicationID,
            formId: budgetID,
            response: .object(["activity_line_items": .array([])])
        )
        XCTAssertTrue(budget.warnings.contains {
            $0.field == "$.activity_line_items" && $0.type == "minItems"
        })
        XCTAssertEqual(budget.form.applicationFormStatus, "in_progress")
    }

    func testSubmitRequiresOrganizationForOrganizationOnlyCompetition() async throws {
        let source = try makeSource(anchorDate)
        let applicationID = try await source.startApplication(
            competitionId: "usda-rd-27-05-open",
            name: "Application Without Organization",
            organizationId: nil
        )
        try await completeRequiredForms(source, applicationID: applicationID)
        do {
            _ = try await source.submit(applicationId: applicationID)
            XCTFail("Expected organization requirement to block submission")
        } catch let error as GrantsError {
            guard case let .server(status, message) = error else { throw error }
            XCTAssertEqual(status, 422)
            XCTAssertEqual(message, "Application requires organization in order to submit")
        }
    }

    func testSeededApplicationAndSavedOpportunityToggles() async throws {
        let source = try makeSource(anchorDate)
        let seeded = try await source.application(id: "sample-application-0001")
        XCTAssertTrue(seeded.applicationForms.allSatisfy {
            $0.isIncludedInSubmission == $0.isRequired
        })
        XCTAssertEqual(seeded.applicationForms.count, 6)
        XCTAssertEqual(seeded.applicationForms.filter { $0.applicationFormStatus == "complete" }.count, 3)
        XCTAssertEqual(seeded.applicationForms.map(\.form.formName), [
            "Application for Federal Assistance (SF-424)",
            "Budget Information for Non-Construction Programs (SF-424A)",
            "Project Narrative Attachment Form",
            "Assurances for Non-Construction Programs (SF-424B)",
            "PROJECT/PERFORMANCE SITE LOCATION(S)",
            "Disclosure of Lobbying Activities (SF-LLL)"
        ])
        XCTAssertEqual(seeded.applicationForms.map(\.formId), [
            "1623b310-85be-496a-b84b-34bdee22a68a",
            "08e6603f-d197-4a60-98cd-d49acb1fc1fd",
            "32165da2-354d-42c0-a986-cf4f2f350039",
            "1d0681f8-26f9-4ff1-a75e-e33477668f73",
            "6ebd786f-cccf-4ee1-a100-61436975025b",
            "778a1485-082a-463e-a61b-6615ccebe027"
        ])
        XCTAssertEqual(
            Set(seeded.applicationForms.filter { $0.applicationFormStatus == "complete" }.map(\.formId)),
            Set([
                "08e6603f-d197-4a60-98cd-d49acb1fc1fd",
                "32165da2-354d-42c0-a986-cf4f2f350039",
                "6ebd786f-cccf-4ee1-a100-61436975025b"
            ])
        )
        let seededSF424 = try XCTUnwrap(seeded.applicationForms.first(where: { $0.formId == "1623b310-85be-496a-b84b-34bdee22a68a" }))
        XCTAssertEqual(seededSF424.applicationFormStatus, "in_progress")
        XCTAssertEqual(seededSF424.applicationResponse["funding_opportunity_number"], .string("HRSA-27-014"))
        XCTAssertEqual(seededSF424.applicationResponse["funding_opportunity_title"], .string("Rural Communities Opioid Response Program – Implementation"))
        XCTAssertEqual(seededSF424.applicationResponse["organization_name"], .string("Bluefield Community Health Center"))
        XCTAssertEqual(seededSF424.applicationResponse["sam_uei"], .string("K7LMN2QX4R91"))
        XCTAssertEqual(seededSF424.applicationResponse["contact_person"], .object([
            "first_name": .string("Dana"),
            "last_name": .string("Reyes")
        ]))
        XCTAssertEqual(seededSF424.applicationResponse["phone_number"], .string("(304) 555-0142"))
        let seededSF424B = try XCTUnwrap(seeded.applicationForms.first(where: { $0.formId == "1d0681f8-26f9-4ff1-a75e-e33477668f73" }))
        let seededSFLLL = try XCTUnwrap(seeded.applicationForms.first(where: { $0.formId == "778a1485-082a-463e-a61b-6615ccebe027" }))
        XCTAssertEqual(seededSF424B.applicationResponse, .object([:]))
        XCTAssertEqual(seededSFLLL.applicationResponse, .object([:]))
        let seededPlaceholderPaths = seeded.applicationForms.flatMap {
            placeholderPaths(in: $0.applicationResponse, path: "$.\($0.formId)")
        }
        XCTAssertTrue(seededPlaceholderPaths.isEmpty, "Seeded responses contain placeholders at \(seededPlaceholderPaths)")
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

    private func completeRequiredForms(_ source: SampleDataSource, applicationID: String) async throws {
        let application = try await source.application(id: applicationID)
        for form in application.applicationForms where form.isRequired {
            let response = RequiredFieldValidator.minimalInstance(schema: form.form.formJsonSchema)
            let result = try await source.saveForm(
                applicationId: applicationID,
                formId: form.formId,
                response: response
            )
            XCTAssertTrue(result.warnings.isEmpty, "Generated response did not satisfy \(form.formId)")
        }
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

    private func placeholderPaths(in value: JSONValue, path: String) -> [String] {
        switch value {
        case .string("Sample"):
            return [path]
        case let .object(values):
            return values.flatMap { placeholderPaths(in: $0.value, path: "\(path).\($0.key)") }
        case let .array(values):
            return values.enumerated().flatMap { placeholderPaths(in: $0.element, path: "\(path).\($0.offset)") }
        default:
            return []
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
