import SGModels
import XCTest
@testable import SGForms

/// Every form exported from `api/src/form_schema/forms` by
/// `Scripts/export_form_fixtures.py` must parse, and every UI-schema
/// `definition` must resolve against its JSON schema.
final class ContractTests: XCTestCase {
    func testEveryExportedFormParsesAndResolves() throws {
        let names = try Fixtures.allFormNames()
        XCTAssertEqual(names.count, 20, "The API registry (_ALL_FORMS) currently defines 20 forms.")

        var report: [String] = ["form | sections | steps | supported | finish on web"]
        for name in names {
            let model = try Fixtures.model(name)
            XCTAssertFalse(model.sections.isEmpty, "\(name) has no sections")
            XCTAssertFalse(model.steps.isEmpty, "\(name) has no steps")
            XCTAssertLessThanOrEqual(model.steps.count, FormStepPlanner.targetStepCount)
            XCTAssertEqual(model.steps.flatMap(\.sectionIDs), model.sections.map(\.id), "\(name) steps must cover sections in order")
            XCTAssertEqual(model.unresolvedDefinitions, [], "\(name) has unresolved definitions")
            for field in model.allFields + model.allFields.flatMap(\.children) where field.kind != .heading && field.kind != .staticText {
                XCTAssertFalse(field.title.isEmpty, "\(name) \(field.path) has no title")
                if field.kind == .select || field.kind == .radio || field.kind == .multiSelect {
                    XCTAssertFalse(field.options.isEmpty, "\(name) \(field.path) has no options")
                }
            }
            let coverage = model.coverage
            report.append("\(name) | \(model.sections.count) | \(model.steps.count) | \(coverage.supported) | \(coverage.finishOnWeb)")
        }
        print("SGForms coverage\n" + report.joined(separator: "\n"))
    }

    func testEveryUIDefinitionResolvesThroughRefsAndAllOf() throws {
        for name in try Fixtures.allFormNames() {
            let definition = try Fixtures.definition(name)
            let resolver = SchemaResolver(root: definition.formJsonSchema)
            for pointer in Self.definitions(in: definition.formUiSchema) {
                XCTAssertNotNil(resolver.schema(at: pointer), "\(name): \(pointer) did not resolve")
            }
        }
    }

    func testSF424Structure() throws {
        let model = try Fixtures.model("SF424_4_0")
        XCTAssertEqual(model.sections.count, 24)
        XCTAssertEqual(model.steps.map(\.title), [
            "Type of application", "Applicant information", "Funding opportunity",
            "Project and funding", "Review and sign"
        ])
        XCTAssertEqual(model.steps[1].sectionIDs, [
            "applicant_information", "organizational_unit", "contact_person", "type_of_applicant"
        ])

        let legalName = try XCTUnwrap(model.field("/properties/organization_name"))
        XCTAssertEqual(legalName.title, "Legal Name")
        XCTAssertEqual(legalName.kind, .text)
        XCTAssertEqual(legalName.maxLength, 60, "allOf from the shared schema is merged")

        let uei = try XCTUnwrap(model.field("/properties/sam_uei"))
        XCTAssertTrue(uei.isReadOnly)
        XCTAssertFalse(uei.isEditable)

        let street = try XCTUnwrap(model.field("/properties/applicant/properties/street1"))
        XCTAssertEqual(street.dataPath.jsonPath, "$.applicant.street1")
        XCTAssertEqual(street.title, "Street 1")

        let country = try XCTUnwrap(model.field("/properties/applicant/properties/country"))
        XCTAssertEqual(country.kind, .select)
        XCTAssertTrue(country.options.contains { $0.title == "USA: UNITED STATES" })

        let email = try XCTUnwrap(model.field("/properties/email"))
        XCTAssertEqual(email.textFormat, .email)
        XCTAssertEqual(try XCTUnwrap(model.field("/properties/phone_number")).textFormat, .phone)
        XCTAssertEqual(try XCTUnwrap(model.field("/properties/applicant_type_code")).kind, .multiSelect)
        XCTAssertEqual(try XCTUnwrap(model.field("/properties/project_start_date")).textFormat, .date)
        XCTAssertEqual(try XCTUnwrap(model.field("/properties/federal_estimated_funding")).textFormat, .currency)
    }

    func testWidgetsAcrossForms() throws {
        let attachments = try Fixtures.model("ProjectNarrativeAttachments_1_2")
        XCTAssertEqual(attachments.allFields.first?.kind, .attachmentArray)

        let abstract = try Fixtures.model("Project_Abstract")
        XCTAssertTrue(abstract.allFields.contains { $0.kind == .attachment })

        let keyContacts = try Fixtures.model("Key_Contacts")
        let list = try XCTUnwrap(keyContacts.allFields.first { $0.kind == .fieldList })
        XCTAssertEqual(list.dataPath.jsonPath, "$.key_contacts")
        XCTAssertEqual(list.minItems, 1)
        XCTAssertEqual(list.maxItems, 4)
        XCTAssertEqual(list.children.first?.dataPath.jsonPath, "$.project_role")
        XCTAssertTrue(list.children.contains { $0.dataPath.jsonPath == "$.name.first_name" })

        let epa = try Fixtures.model("EPA4700_4")
        XCTAssertTrue(epa.allFields.contains { $0.kind == .radio && $0.options.count == 2 })

        let budget = try Fixtures.model("SF424A")
        XCTAssertTrue(budget.allFields.allSatisfy { $0.kind == .finishOnWeb })
        XCTAssertEqual(budget.coverage.supported, 0)

        let construction = try Fixtures.model("SF424C")
        let table = try XCTUnwrap(construction.allFields.first { $0.kind == .table })
        XCTAssertFalse(table.isSupported)
        XCTAssertFalse(table.tableColumns.isEmpty)

        let short = try Fixtures.model("SF424_Short_3_0")
        XCTAssertTrue(short.allFields.contains { $0.kind == .staticText && !($0.content ?? "").isEmpty })
    }

    func testGenericStepsBalanceSections() throws {
        let model = try Fixtures.model("SFLLL_2_0")
        XCTAssertEqual(model.steps.count, 5)
        XCTAssertFalse(model.steps.contains { $0.sections.isEmpty })
        let single = try Fixtures.model("BudgetNarrativeAttachments_1_2")
        XCTAssertEqual(single.steps.count, 1)
    }

    private static func definitions(in node: JSONValue) -> [String] {
        switch node {
        case let .array(items):
            return items.flatMap(definitions(in:))
        case let .object(object):
            var result: [String] = []
            var own: [String] = []
            if case let .string(pointer)? = object["definition"] { own.append(pointer) }
            if case let .array(pointers)? = object["definition"] { own += pointers.compactMap(\.formString) }
            result += own
            if let children = object["children"] {
                if case let .object(table) = children, case let .array(rows)? = table["rows"] {
                    // Table cells point into the value of the multiField definition.
                    for row in rows {
                        for cell in row["cells"]?.formArray ?? [] {
                            if let pointer = cell.formString("definition"), let parent = own.first {
                                result.append(parent + pointer)
                            }
                        }
                    }
                } else {
                    result += definitions(in: children)
                }
            }
            return result
        default:
            return []
        }
    }
}

final class PreviewSampleTests: XCTestCase {
    func testBundledSF424MatchesExportedFixture() throws {
        let bundled = try FormPreviewSamples.sf424Definition()
        let fixture = try Fixtures.definition("SF424_4_0")
        XCTAssertEqual(bundled.formJsonSchema, fixture.formJsonSchema)
        XCTAssertEqual(bundled.formUiSchema, fixture.formUiSchema)
    }

    func testSF424ScenariosMatchReference10() throws {
        let reference = try FormPreviewSamples.sf424ApplicantInformation(.referenceFields)
        XCTAssertEqual(reference.stepTitle, "Applicant information")
        XCTAssertEqual(reference.stepIndex, 1)
        XCTAssertEqual(reference.stepCount, 5)
        XCTAssertEqual(reference.sections.first?.fields.map(\.path), FormPreviewSamples.referencePointers)
        XCTAssertEqual(reference.errors, [])

        let invalid = try FormPreviewSamples.sf424ApplicantInformation(.invalidEmail)
        XCTAssertEqual(invalid.errors, [
            FieldError(path: "$.email", message: "Enter a valid email address, like name@organization.org")
        ])

        let full = try FormPreviewSamples.sf424ApplicantInformation(.fullStepEmpty)
        XCTAssertEqual(full.sections.map(\.id), ["applicant_information", "organizational_unit", "contact_person", "type_of_applicant"])
        XCTAssertFalse(full.errors.isEmpty)
    }
}
