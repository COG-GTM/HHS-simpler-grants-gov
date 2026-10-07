import SGModels
import XCTest
@testable import SGForms

final class ValueTests: XCTestCase {
    func testWritesPreserveUnknownKeys() {
        var response: JSONValue = [
            "unknown_top": ["keep": true],
            "applicant": ["street1": "1 Main St", "legacy_field": "keep me"],
            "key_contacts": [["project_role": "PI", "server_only": 7]]
        ]
        response.setValue("Bluefield", at: FieldPath(jsonPath: "$.applicant.city"))
        response.setValue("Jane", at: FieldPath(jsonPath: "$.key_contacts[0].name.first_name"))
        response.setValue("dana@bluefieldchc.org", at: FieldPath(keys: ["email"]))

        XCTAssertEqual(response.value(at: FieldPath(jsonPath: "$.unknown_top.keep")), .bool(true))
        XCTAssertEqual(response.value(at: FieldPath(jsonPath: "$.applicant.legacy_field")), "keep me")
        XCTAssertEqual(response.value(at: FieldPath(jsonPath: "$.applicant.street1")), "1 Main St")
        XCTAssertEqual(response.value(at: FieldPath(jsonPath: "$.applicant.city")), "Bluefield")
        XCTAssertEqual(response.value(at: FieldPath(jsonPath: "$.key_contacts[0].server_only")), 7)
        XCTAssertEqual(response.value(at: FieldPath(jsonPath: "$.key_contacts[0].name.first_name")), "Jane")
    }

    func testRoundTripThroughEncodingKeepsEverything() throws {
        let original: JSONValue = [
            "x_vendor": ["nested": [1, 2, ["deep": "value"]]],
            "organization_name": "Old",
            "certification_agree": true
        ]
        var edited = original
        edited.setValue("New", at: FieldPath(keys: ["organization_name"]))
        let data = try JSONEncoder.sg.encode(edited)
        let decoded = try JSONDecoder.sg.decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded["x_vendor"], original["x_vendor"])
        XCTAssertEqual(decoded["certification_agree"], .bool(true))
        XCTAssertEqual(decoded["organization_name"], "New")
    }

    func testClearingRemovesOnlyThatKey() {
        var response: JSONValue = ["applicant": ["city": "X", "other": "Y"], "email": "a@b.org"]
        response.setValue(nil, at: FieldPath(jsonPath: "$.applicant.city"))
        response.setValue(nil, at: FieldPath(keys: ["email"]))
        XCTAssertEqual(response, ["applicant": ["other": "Y"]])
    }

    func testRemoveListEntry() {
        var response: JSONValue = ["key_contacts": [["project_role": "A"], ["project_role": "B"], ["project_role": "C"]]]
        response.removeElement(at: FieldPath(jsonPath: "$.key_contacts[1]"))
        XCTAssertEqual(response, ["key_contacts": [["project_role": "A"], ["project_role": "C"]]])
    }

    func testFieldPathParsing() {
        XCTAssertEqual(FieldPath(jsonPath: "$.a.b[2].c").components, [.key("a"), .key("b"), .index(2), .key("c")])
        XCTAssertEqual(FieldPath(definition: "/properties/key_contacts/items/properties/name/properties/first_name", indexes: [3]).jsonPath,
                       "$.key_contacts[3].name.first_name")
        XCTAssertEqual(FieldPath(definition: "/properties/applicant/properties/street1").jsonPath, "$.applicant.street1")
    }

    func testEditingThroughModelFieldsPreservesSampleResponse() throws {
        let model = try Fixtures.model("SF424_4_0")
        var response: JSONValue = ["applicant_name": "Civic Resilience Collaborative", "unknown": [1]]
        for field in model.allFields where field.kind == .text && field.isEditable {
            response.setValue("x", at: field.dataPath)
        }
        XCTAssertEqual(response["applicant_name"], "Civic Resilience Collaborative")
        XCTAssertEqual(response["unknown"], [1])
        XCTAssertEqual(response.value(at: FieldPath(jsonPath: "$.contact_person.first_name")), "x")
    }
}
