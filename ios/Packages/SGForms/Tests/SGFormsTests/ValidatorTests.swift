import SGModels
import XCTest
@testable import SGForms

final class ValidatorTests: XCTestCase {
    private var sf424: FormModel!

    override func setUpWithError() throws {
        sf424 = try Fixtures.model("SF424_4_0")
    }

    private func errors(_ values: JSONValue, section: String, in model: FormModel? = nil) throws -> [String: String] {
        let model = model ?? sf424!
        let section = try XCTUnwrap(model.section(id: section))
        let errors = FormValidator.validate(values, section: section, model: model)
        return Dictionary(uniqueKeysWithValues: errors.map { ($0.path, $0.message) })
    }

    func testInvalidEmailUsesPlainLanguageMessageFromReference10() throws {
        let result = try errors(["email": "dana@bluefieldchc"], section: "contact_person")
        XCTAssertEqual(result["$.email"], "Enter a valid email address, like name@organization.org")
    }

    func testValidEmailPasses() throws {
        let result = try errors(["email": "dana@bluefieldchc.org"], section: "contact_person")
        XCTAssertNil(result["$.email"])
    }

    func testRequiredTopLevelAndNestedFields() throws {
        let result = try errors(.object([:]), section: "contact_person")
        XCTAssertEqual(result["$.email"], "Email is required")
        XCTAssertEqual(result["$.phone_number"], "Telephone Number is required")
        XCTAssertEqual(result["$.contact_person.first_name"], "First Name is required")
        XCTAssertNil(result["$.contact_person.middle_name"], "optional nested field")
        XCTAssertNil(result["$.fax"])
    }

    func testBlankStringsCountAsMissing() throws {
        let result = try errors(["organization_name": "   "], section: "applicant_information")
        XCTAssertEqual(result["$.organization_name"], "Legal Name is required")
    }

    func testReadOnlyPrefilledFieldsNeverBlock() throws {
        let result = try errors(.object([:]), section: "applicant_information")
        XCTAssertNil(result["$.sam_uei"])
    }

    func testConditionalAddressRequiresStateAndZipOnlyForUSA() throws {
        let base: [String: JSONValue] = ["street1": "1 Main St", "city": "Bluefield"]
        var applicant = base
        applicant["country"] = "USA: UNITED STATES"
        var result = try errors(["applicant": .object(applicant)], section: "applicant_information")
        XCTAssertEqual(result["$.applicant.state"], "Choose an option for State")
        XCTAssertEqual(result["$.applicant.zip_code"], "Zip / Postal Code is required")

        applicant["country"] = "CAN: CANADA"
        result = try errors(["applicant": .object(applicant)], section: "applicant_information")
        XCTAssertNil(result["$.applicant.state"])
        XCTAssertNil(result["$.applicant.zip_code"])
    }

    func testConditionalRevisionRequiresRevisionFields() throws {
        let section = "application_type_and_revision"
        var result = try errors(["application_type": "New"], section: section)
        XCTAssertNil(result["$.revision_type"])
        result = try errors(["application_type": "Revision"], section: section)
        XCTAssertNotNil(result["$.revision_type"])
        result = try errors(["application_type": "Continuation"], section: "federal_award")
        XCTAssertNotNil(result["$.federal_award_identifier"])
    }

    func testConditionalContainsForOtherApplicantType() throws {
        var result = try errors(["applicant_type_code": ["X: Other (specify)"]], section: "type_of_applicant")
        XCTAssertEqual(result["$.applicant_type_other_specify"], "Type of Applicant: Other (Specify) is required".replacingOccurrences(of: "Type of Applicant: Other (Specify)", with: sf424.field("/properties/applicant_type_other_specify")!.title))
        result = try errors(["applicant_type_code": ["A: State Government"]], section: "type_of_applicant")
        XCTAssertNil(result["$.applicant_type_other_specify"])
    }

    func testConditionalNotRequiredPairs() throws {
        let cd511 = try Fixtures.model("CD511")
        let section = try XCTUnwrap(cd511.sectionContaining("/properties/award_number"))
        let missingBoth = FormValidator.validate(.object([:]), section: section, model: cd511).map(\.path)
        XCTAssertTrue(missingBoth.contains("$.award_number"))
        XCTAssertTrue(missingBoth.contains("$.project_name"))
        let withAward = FormValidator.validate(["award_number": "AB-123"], section: section, model: cd511).map(\.path)
        XCTAssertFalse(withAward.contains("$.project_name"))
    }

    func testLengthPatternTypeEnumAndDate() throws {
        var result = try errors(["organization_name": .string(String(repeating: "a", count: 61))], section: "applicant_information")
        XCTAssertEqual(result["$.organization_name"], "Use 60 characters or fewer")

        result = try errors(["employer_taxpayer_identification_number": "12345"], section: "applicant_information")
        XCTAssertEqual(result["$.employer_taxpayer_identification_number"], "Use at least 9 characters")

        result = try errors(["federal_estimated_funding": "12.5"], section: "estimated_funding")
        XCTAssertEqual(result["$.federal_estimated_funding"], "Enter a dollar amount, like 1500.00")
        result = try errors(["federal_estimated_funding": "1500.00"], section: "estimated_funding")
        XCTAssertNil(result["$.federal_estimated_funding"])

        result = try errors(["applicant": ["street1": "1 Main", "city": "X", "country": "Atlantis"]], section: "applicant_information")
        XCTAssertEqual(result["$.applicant.country"], "Choose one of the listed options")

        result = try errors(["project_start_date": "2026-02-30"], section: "project_dates")
        XCTAssertEqual(result["$.project_start_date"], "Enter a valid date, like 2026-01-31")
        result = try errors(["project_start_date": "2026-02-28"], section: "project_dates")
        XCTAssertNil(result["$.project_start_date"])

        result = try errors(["organization_name": 42], section: "applicant_information")
        XCTAssertEqual(result["$.organization_name"], "Check this answer")
    }

    func testExactLengthMinimumAndMaximum() throws {
        let schema: JSONValue = [
            "type": "object",
            "properties": [
                "uei": ["type": "string", "minLength": 12, "maxLength": 12, "title": "UEI"],
                "percent": ["type": "integer", "minimum": 0, "maximum": 100, "title": "Percent"]
            ]
        ]
        let ui: JSONValue = [[
            "type": "section", "name": "s", "label": "S",
            "children": [
                ["type": "field", "definition": "/properties/uei"],
                ["type": "field", "definition": "/properties/percent"]
            ]
        ]]
        let model = try FormModel(definition: FormDefinition(formId: "t", formJsonSchema: schema, formUiSchema: ui))
        var result = try errors(["uei": "SHORT", "percent": 101], section: "s", in: model)
        XCTAssertEqual(result["$.uei"], "Use exactly 12 characters")
        XCTAssertEqual(result["$.percent"], "Enter 100 or less")
        result = try errors(["uei": "K7LMN2QX4R91", "percent": -1], section: "s", in: model)
        XCTAssertNil(result["$.uei"])
        XCTAssertEqual(result["$.percent"], "Enter 0 or more")
        result = try errors(["percent": 2.5], section: "s", in: model)
        XCTAssertEqual(result["$.percent"], "Enter a whole number")
    }

    func testFieldListMinItemsAndPerEntryValidation() throws {
        let model = try Fixtures.model("Key_Contacts")
        let section = try XCTUnwrap(model.sections.first)
        var result = FormValidator.validate(.object([:]), section: section, model: model).map(\.path)
        XCTAssertTrue(result.contains("$.key_contacts[0].project_role"), "minItems shows one blank entry to fill")

        let values: JSONValue = ["key_contacts": [
            ["project_role": "PI", "email": "bad"],
            ["project_role": "Co-PI"]
        ]]
        let errors = FormValidator.validate(values, section: section, model: model)
        result = errors.map(\.path)
        XCTAssertTrue(result.contains("$.key_contacts[0].email"))
        XCTAssertEqual(errors.first { $0.path == "$.key_contacts[0].email" }?.message, "Enter a valid email address, like name@organization.org")
        XCTAssertTrue(result.contains("$.key_contacts[1].email"))
        XCTAssertTrue(result.contains("$.key_contacts[1].name.first_name"))
        XCTAssertFalse(result.contains("$.key_contacts[0].project_role"))
    }

    func testProgressCountsCompletedSteps() throws {
        let empty = sf424.progress(values: .object([:]))
        XCTAssertEqual(empty.totalSteps, 5)
        // "Funding opportunity" only has server-filled (read-only) fields.
        XCTAssertEqual(empty.stepCompletion, [false, false, true, false, false])
        XCTAssertEqual(empty.requiredAnswered, 0)
        XCTAssertGreaterThan(empty.requiredTotal, 20)
        XCTAssertEqual(empty.firstIncompleteStep, 0)

        let partial = sf424.progress(values: ["organization_name": "Bluefield Community Health Center"])
        XCTAssertEqual(partial.requiredAnswered, 1)
        XCTAssertGreaterThan(partial.fraction, 0)
    }
}
