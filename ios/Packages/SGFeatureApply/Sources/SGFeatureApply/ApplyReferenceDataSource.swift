import Foundation
import SGForms
import SGModels

/// Fictional sample data for previews, snapshots and demo deep links.
public actor ApplyReferenceDataSource: GrantsDataSource {
    public enum Scenario: Equatable, Sendable {
        case inProgress
        case allComplete
        case empty
    }

    public private(set) var saveCount = 0
    public private(set) var submitCount = 0
    public private(set) var lastSavedResponse: JSONValue?

    private let scenario: Scenario
    private let saveFailure: GrantsError?
    private let submitFailure: GrantsError?
    private let preview = PreviewDataSource()
    private var applicationFixture: Application

    public init(
        scenario: Scenario,
        saveFailure: GrantsError? = nil,
        submitFailure: GrantsError? = nil,
        sf424Definition: FormDefinition? = nil
    ) {
        self.scenario = scenario
        self.saveFailure = saveFailure
        self.submitFailure = submitFailure
        applicationFixture = Self.makeApplication(scenario: scenario, sf424Definition: sf424Definition)
    }

    public static func progressStore(for scenario: Scenario) -> InMemoryFormProgressStore {
        let initialSteps: [String: Set<String>]
        let completeForms: Set<String>
        switch scenario {
        case .inProgress:
            initialSteps = ["apply-demo/sf424": ["step-1", "step-2"]]
            completeForms = []
        case .allComplete:
            initialSteps = [:]
            completeForms = Set(Self.formIds)
        case .empty:
            initialSteps = [:]
            completeForms = []
        }
        return InMemoryFormProgressStore(
            completedSections: initialSteps,
            completeForms: completeForms
        )
    }

    public func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        try await preview.searchOpportunities(request)
    }

    public func opportunity(id: String) async throws -> OpportunityDetail {
        if id == "hrsa" || id == "hrsa-27-014" {
            return Self.makeOpportunity()
        }
        return try await preview.opportunity(id: id)
    }

    public func currentUser() async throws -> UserProfile {
        try await preview.currentUser()
    }

    public func organizations() async throws -> [Organization] {
        [Self.organization]
    }

    public func applications() async throws -> [ApplicationSummary] {
        guard scenario != .empty else { return [] }
        let competition = ApplicationCompetition(
            competitionId: applicationFixture.competition.competitionId,
            competitionTitle: applicationFixture.competition.competitionTitle,
            openingDate: applicationFixture.competition.openingDate,
            closingDate: applicationFixture.competition.closingDate,
            isOpen: applicationFixture.competition.isOpen,
            opportunity: ApplicationOpportunity(
                opportunityId: "hrsa",
                opportunityTitle: Self.opportunityTitle,
                agencyName: Self.agencyName
            )
        )
        return [
            ApplicationSummary(
                applicationId: applicationFixture.applicationId,
                applicationName: applicationFixture.applicationName,
                applicationStatus: applicationFixture.applicationStatus,
                organization: applicationFixture.organization,
                competition: competition
            )
        ]
    }

    public func startApplication(
        competitionId: String,
        name: String,
        organizationId: String?
    ) async throws -> String {
        "apply-demo"
    }

    public func application(id: String) async throws -> Application {
        guard scenario != .empty, id == applicationFixture.applicationId else {
            throw GrantsError.notFound
        }
        return applicationFixture
    }

    public func form(id: String) async throws -> FormDefinition {
        guard let form = Self.forms.first(where: { $0.formId == id }) else {
            throw GrantsError.notFound
        }
        return form
    }

    public func saveForm(
        applicationId: String,
        formId: String,
        response: JSONValue
    ) async throws -> FormSaveResult {
        saveCount += 1
        lastSavedResponse = response
        if let saveFailure { throw saveFailure }
        guard let index = applicationFixture.applicationForms.firstIndex(where: {
            $0.formId == formId || $0.applicationFormId == formId
        }) else {
            throw GrantsError.notFound
        }
        var forms = applicationFixture.applicationForms
        let original = forms[index]
        let updated = ApplicationForm(
            applicationFormId: original.applicationFormId,
            formId: original.formId,
            form: original.form,
            applicationResponse: response,
            applicationFormStatus: original.applicationFormStatus,
            isRequired: original.isRequired,
            isIncludedInSubmission: original.isIncludedInSubmission,
            applicationId: original.applicationId,
            applicationName: original.applicationName
        )
        forms[index] = updated
        applicationFixture = Application(
            applicationId: applicationFixture.applicationId,
            applicationName: applicationFixture.applicationName,
            applicationStatus: applicationFixture.applicationStatus,
            competition: applicationFixture.competition,
            organization: applicationFixture.organization,
            applicationForms: forms,
            formValidationWarnings: applicationFixture.formValidationWarnings,
            intendsToAddOrganization: applicationFixture.intendsToAddOrganization
        )
        return FormSaveResult(warnings: [], form: updated)
    }

    public func submit(applicationId: String) async throws -> SubmissionResult {
        submitCount += 1
        if let submitFailure { throw submitFailure }
        return SubmissionResult(applicationId: applicationId, trackingNumber: "GRANT14102837")
    }

    public func savedOpportunityIds() async throws -> Set<String> {
        try await preview.savedOpportunityIds()
    }

    public func setSaved(_ saved: Bool, opportunityId: String) async throws {
        try await preview.setSaved(saved, opportunityId: opportunityId)
    }

    private static let formIds = ["sf424", "sf424a", "narrative", "budget", "site", "sflll"]
    private static let opportunityTitle =
        "Rural Communities Opioid Response Program – Implementation"
    private static let agencyName = "Health Resources and Services Administration"
    private static let organizationName = "Bluefield Community Health Center"
    private static let organization = Organization(
        organizationId: "bluefield-community-health",
        samGovEntity: SamGovEntity(
            uei: "K7LMN2QX4R91",
            legalBusinessName: organizationName
        )
    )

    private static let forms: [FormDefinition] = {
        let sf424 = FormDefinition(
            formId: "sf424",
            formName: "Application for Federal Assistance (SF-424)",
            shortFormName: "SF-424",
            formJsonSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "organization_name": fieldSchema("Legal name"),
                    "sam_uei": fieldSchema("Unique Entity ID (UEI)"),
                    "applicant_type_code": fieldSchema("Type of applicant"),
                    "email": fieldSchema("Point of contact email"),
                    "phone_number": fieldSchema("Phone")
                ])
            ]),
            formUiSchema: .array([
                section("applicant", "Applicant information", [
                    "organization_name", "sam_uei", "applicant_type_code", "email", "phone_number"
                ]),
                section("project", "Project information", []),
                section("contacts", "Contacts", []),
                section("locations", "Project locations", []),
                section("certifications", "Certifications", [])
            ])
        )
        let names: [(String, String, String)] = [
            ("sf424a", "Budget Information (SF-424A)", "SF-424A"),
            ("narrative", "Project Narrative", "Narrative"),
            ("budget", "Budget Justification", "Budget"),
            ("site", "Project/Performance Site Location", "Site"),
            ("sflll", "Disclosure of Lobbying Activities (SF-LLL)", "SF-LLL")
        ]
        return [sf424] + names.map { id, name, shortName in
            FormDefinition(
                formId: id,
                formName: name,
                shortFormName: shortName,
                formJsonSchema: .object(["type": .string("object"), "properties": .object([:])]),
                formUiSchema: .array([
                    section("overview", "Overview", []),
                    section("details", "Details", []),
                    section("attachments", "Attachments", []),
                    section("certifications", "Certifications", []),
                    section("review", "Review", [])
                ])
            )
        }
    }()

    private static func fieldSchema(_ title: String) -> JSONValue {
        .object(["type": .string("string"), "title": .string(title)])
    }

    private static func section(_ id: String, _ title: String, _ properties: [String]) -> JSONValue {
        .object([
            "type": .string("section"),
            "name": .string(id),
            "label": .string(title),
            "children": .array(properties.map { property in
                .object([
                    "type": .string("field"),
                    "definition": .string("/properties/\(property)"),
                    "label": .string(property)
                ])
            })
        ])
    }

    private static func makeApplication(
        scenario: Scenario,
        sf424Definition: FormDefinition? = nil
    ) -> Application {
        let allComplete = scenario == .allComplete
        let applicationForms = forms.enumerated().map { index, storedForm in
            let form: FormDefinition
            if index == 0, let sf424Definition {
                form = FormDefinition(
                    formId: storedForm.formId,
                    formName: sf424Definition.formName,
                    shortFormName: sf424Definition.shortFormName,
                    formVersion: sf424Definition.formVersion,
                    formType: sf424Definition.formType,
                    formJsonSchema: sf424Definition.formJsonSchema,
                    formUiSchema: sf424Definition.formUiSchema,
                    formRuleSchema: sf424Definition.formRuleSchema,
                    agencyCode: sf424Definition.agencyCode,
                    ombNumber: sf424Definition.ombNumber
                )
            } else {
                form = storedForm
            }
            let complete = allComplete || [1, 2, 4].contains(index)
            let response: JSONValue = index == 0
                ? .object([
                    "email": .string("dana@bluefieldchc"),
                    "phone_number": .string("(304) 555-0142"),
                    "applicant_type_code": .string("Nonprofit with 501(c)(3) status")
                ])
                : .object([:])
            return ApplicationForm(
                applicationFormId: "apply-form-\(form.formId)",
                formId: form.formId,
                form: form,
                applicationResponse: response,
                applicationFormStatus: complete ? "complete" : (index == 0 ? "in_progress" : "not_started"),
                isRequired: true,
                applicationId: "apply-demo"
            )
        }
        let competition = Competition(
            competitionId: "hrsa-27-014",
            competitionTitle: opportunityTitle,
            openingDate: "2026-09-01",
            closingDate: "2026-12-12",
            isOpen: true,
            isSimplerGrantsEnabled: true,
            opportunityId: "hrsa"
        )
        return Application(
            applicationId: "apply-demo",
            applicationName: opportunityTitle,
            applicationStatus: "in_progress",
            competition: competition,
            organization: organization,
            applicationForms: applicationForms
        )
    }

    private static func makeOpportunity() -> OpportunityDetail {
        OpportunityDetail(
            opportunity: Opportunity(
                opportunityId: "hrsa",
                opportunityNumber: "HRSA-27-014",
                opportunityTitle: opportunityTitle,
                agencyCode: "HRSA",
                agencyName: agencyName,
                topLevelAgencyName: "Department of Health and Human Services",
                opportunityStatus: .posted,
                summary: OpportunitySummary(closeDate: "2026-12-12")
            )
        )
    }
}
