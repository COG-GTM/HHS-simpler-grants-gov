import Foundation
import XCTest
@testable import SGModels

final class SGModelsTests: XCTestCase {
    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    func testSearchResponseDecodesCapturedSearchAndFacets() throws {
        let response = try JSONDecoder.sg.decode(SearchResponse.self, from: fixture("search"))

        XCTAssertEqual(response.paginationInfo.totalRecords, 144)
        XCTAssertFalse(response.data.isEmpty)
        XCTAssertEqual(response.facetCounts["opportunity_status"]?["posted"], 114)
        XCTAssertFalse(response.data[0].opportunityId.isEmpty)
    }

    func testOpportunityDetailDecodesCompetitionAndFormFamily() throws {
        let response = try JSONDecoder.sg.decode(
            Envelope<OpportunityDetail>.self,
            from: fixture("opportunity-detail")
        )
        let detail = response.data
        let competition = try XCTUnwrap(detail.competitions.first)
        let formIds = Set(competition.competitionForms.map(\.form.formId))

        XCTAssertTrue(competition.isOpen)
        XCTAssertTrue(competition.isSimplerGrantsEnabled)
        XCTAssertTrue(formIds.isSuperset(of: Set([
            "1623b310-85be-496a-b84b-34bdee22a68a",
            "08e6603f-d197-4a60-98cd-d49acb1fc1fd",
            "1d0681f8-26f9-4ff1-a75e-e33477668f73"
        ])))
        XCTAssertEqual(detail.opportunityId, "a32ae2fa-8a39-4b8d-8acc-0f55ad458c55")
    }

    func testUserProfileDecodesCapturedUser() throws {
        let response = try JSONDecoder.sg.decode(
            Envelope<UserProfile>.self,
            from: fixture("user")
        )

        XCTAssertEqual(response.data.userId, "f15c7491-7ebc-4f4f-8de6-3ac0594d9c63")
        XCTAssertEqual(response.data.email, "fake_mail@mail.com")
    }

    func testOrganizationsDecodeCapturedSAMEntity() throws {
        let response = try JSONDecoder.sg.decode(
            Envelope<[Organization]>.self,
            from: fixture("organizations")
        )

        XCTAssertEqual(response.data.first?.samGovEntity?.uei, "FAKEUEI11111")
        XCTAssertEqual(response.data.first?.samGovEntity?.legalBusinessName, "Sally's Soup Emporium")
    }

    func testUserApplicationsDecodeCapturedList() throws {
        let response = try JSONDecoder.sg.decode(
            Envelope<[ApplicationSummary]>.self,
            from: fixture("user-applications")
        )

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data.first?.applicationStatus, "in_progress")
        XCTAssertEqual(response.data.first?.competition.isOpen, true)
    }

    func testApplicationGetDecodesCapturedForms() throws {
        let response = try JSONDecoder.sg.decode(
            Envelope<Application>.self,
            from: fixture("application")
        )

        XCTAssertEqual(response.data.applicationId, "fd71c0d3-ace2-425b-9496-966a3333b3fa")
        XCTAssertEqual(response.data.applicationForms.count, 7)
        XCTAssertEqual(response.data.applicationForms.first?.form.formId, "1623b310-85be-496a-b84b-34bdee22a68a")
    }

    func testSF424FormGetDecodesCapturedSchemas() throws {
        let response = try JSONDecoder.sg.decode(
            Envelope<FormDefinition>.self,
            from: fixture("form-sf424")
        )

        XCTAssertEqual(response.data.formId, "1623b310-85be-496a-b84b-34bdee22a68a")
        XCTAssertNotNil(response.data.formJsonSchema["properties"])
        if case .array = response.data.formUiSchema {
        } else {
            XCTFail("Expected the captured SF-424 UI schema to be an array")
        }
    }

    func testSearchRequestEncodesOneOfFiltersAndOmitsEmptyValues() throws {
        let request = SearchRequest(
            query: "community health",
            filters: SearchFilters(opportunityStatus: ["posted"]),
            pagination: SearchPagination(
                pageOffset: 1,
                pageSize: 5,
                sortOrder: [SortOrder(orderBy: "post_date", sortDirection: "descending")]
            )
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder.sg.encode(request)) as? [String: Any]
        )
        let filters = try XCTUnwrap(json["filters"] as? [String: Any])
        let status = try XCTUnwrap(filters["opportunity_status"] as? [String: Any])

        XCTAssertEqual(status["one_of"] as? [String], ["posted"])
        XCTAssertNil(filters["applicant_type"])
        XCTAssertEqual(json["query_operator"] as? String, "AND")
    }

    func testJSONValuePathHelpers() throws {
        let value = try JSONDecoder.sg.decode(
            JSONValue.self,
            from: Data(#"{"data":[{"name":"Dana"}]}"#.utf8)
        )

        XCTAssertEqual(value.value(at: "data[0].name"), .string("Dana"))
        XCTAssertEqual(value.value(at: ["data", "0", "name"]), .string("Dana"))
    }

    func testPreviewAuthenticatorReturnsDemoUser() async throws {
        let user = try await PreviewAuthenticator().signIn(pivRequired: false)

        XCTAssertEqual(user.firstName, "Dana")
        XCTAssertEqual(user.lastName, "Reyes")
        XCTAssertEqual(user.email, "dana.reyes@example.org")
    }
}
