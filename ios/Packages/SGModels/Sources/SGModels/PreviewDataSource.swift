import Foundation

private enum PreviewFixtures {
    static let sf424 = FormDefinition(
        formId: "1623b310-85be-496a-b84b-34bdee22a68a",
        formName: "Application for Federal Assistance (SF-424)",
        shortFormName: "SF-424",
        formVersion: "4.0",
        formJsonSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "applicant_name": .object(["type": .string("string"), "title": .string("Applicant name")])
            ]),
            "required": .array([.string("applicant_name")])
        ])
    )

    static let sf424A = FormDefinition(
        formId: "08e6603f-d197-4a60-98cd-d49acb1fc1fd",
        formName: "Budget Information for Non-Construction Programs (SF-424A)",
        shortFormName: "SF-424A",
        formVersion: "1.0",
        formJsonSchema: .object(["type": .string("object"), "properties": .object([:])])
    )

    static let sf424B = FormDefinition(
        formId: "1d0681f8-26f9-4ff1-a75e-e33477668f73",
        formName: "Assurances for Non-Construction Programs (SF-424B)",
        shortFormName: "SF-424B",
        formVersion: "1.0",
        formJsonSchema: .object(["type": .string("object"), "properties": .object([:])])
    )

    static let requiredForms = [
        CompetitionForm(isRequired: true, form: sf424),
        CompetitionForm(isRequired: true, form: sf424A),
        CompetitionForm(isRequired: true, form: sf424B)
    ]

    static let openCompetition = Competition(
        competitionId: "sample-community-health-competition",
        competitionTitle: "Community Health Resilience Planning",
        openingDate: "2026-09-01",
        closingDate: "2027-01-15",
        isOpen: true,
        isSimplerGrantsEnabled: true,
        openToApplicants: ["nonprofit", "local_government"],
        competitionForms: requiredForms
    )

    static let posted = Opportunity(
        opportunityId: "sample-community-health",
        opportunityNumber: "HHS-SAMPLE-2027-01",
        opportunityTitle: "Community Health Resilience Planning Grants",
        agencyCode: "HHS",
        agencyName: "Department of Health and Human Services",
        topLevelAgencyName: "Department of Health and Human Services",
        category: "health",
        opportunityStatus: .posted,
        summary: OpportunitySummary(
            summaryDescription: "Support local partnerships improving access to preventive care and health services.",
            isCostSharing: false,
            closeDate: "2027-01-15",
            postDate: "2026-09-01",
            awardFloor: 50_000,
            awardCeiling: 500_000,
            estimatedTotalProgramFunding: 5_000_000,
            expectedNumberOfAwards: 12,
            applicantTypes: ["nonprofit", "local_government"],
            fundingCategories: ["health"],
            fundingInstruments: ["grant"],
            applicantEligibilityDescription: "Eligible nonprofit organizations and local governments.",
            isForecast: false
        ),
        opportunityAssistanceListings: [
            OpportunityAssistanceListing(
                assistanceListingNumber: "93.999",
                programTitle: "Community Health Resilience"
            )
        ],
        tagline: "Planning for healthier, more resilient communities."
    )

    static let closingSoon = Opportunity(
        opportunityId: "sample-rural-clinics",
        opportunityNumber: "HHS-SAMPLE-2026-04",
        opportunityTitle: "Rural Clinic Modernization Grants",
        agencyCode: "HRSA",
        agencyName: "Health Resources and Services Administration",
        topLevelAgencyName: "Department of Health and Human Services",
        category: "health",
        opportunityStatus: .posted,
        summary: OpportunitySummary(
            summaryDescription: "Modernize essential equipment and patient spaces at rural community clinics.",
            isCostSharing: true,
            closeDate: "2026-11-02",
            postDate: "2026-08-20",
            awardFloor: 100_000,
            awardCeiling: 1_000_000,
            estimatedTotalProgramFunding: 10_000_000,
            expectedNumberOfAwards: 20,
            applicantTypes: ["nonprofit", "public_health_district"],
            fundingCategories: ["health", "community_development"],
            fundingInstruments: ["grant"],
            applicantEligibilityDescription: "Rural clinics and eligible public health organizations.",
            isForecast: false
        ),
        opportunityAssistanceListings: [
            OpportunityAssistanceListing(
                assistanceListingNumber: "93.888",
                programTitle: "Rural Health Facilities"
            )
        ],
        tagline: "A sample listing with a deadline approaching."
    )

    static let forecasted = Opportunity(
        opportunityId: "sample-climate-planning",
        opportunityNumber: "EPA-SAMPLE-2027-02",
        opportunityTitle: "Climate-Ready Community Planning Award",
        agencyCode: "EPA",
        agencyName: "Environmental Protection Agency",
        topLevelAgencyName: "Environmental Protection Agency",
        category: "environment",
        opportunityStatus: .forecasted,
        summary: OpportunitySummary(
            summaryDescription: "A forecasted funding opportunity for community climate adaptation planning.",
            forecastedCloseDate: "2027-05-15",
            forecastedPostDate: "2027-02-01",
            awardFloor: 75_000,
            awardCeiling: 750_000,
            expectedNumberOfAwards: 15,
            applicantTypes: ["local_government", "tribal_government"],
            fundingCategories: ["environment", "community_development"],
            fundingInstruments: ["cooperative_agreement"],
            applicantEligibilityDescription: "Local and tribal governments.",
            isForecast: true
        ),
        opportunityAssistanceListings: [
            OpportunityAssistanceListing(
                assistanceListingNumber: "66.777",
                programTitle: "Climate Adaptation Planning"
            )
        ],
        tagline: "Forecasted sample data; dates and details may change."
    )

    static let opportunities = [posted, closingSoon, forecasted]
    static let details = [
        OpportunityDetail(opportunity: posted, competitions: [openCompetition]),
        OpportunityDetail(opportunity: closingSoon),
        OpportunityDetail(opportunity: forecasted)
    ]

    static let organization = Organization(
        organizationId: "sample-civic-resilience-collaborative",
        samGovEntity: SamGovEntity(
            uei: "DEMOUEI12345",
            legalBusinessName: "Civic Resilience Collaborative",
            expirationDate: "2027-12-31",
            ebizPocEmail: "grants@example.org",
            ebizPocFirstName: "Morgan",
            ebizPocLastName: "Lee"
        )
    )

    static let applicationId = "sample-application-in-progress"
    static let applicationForms = [
        ApplicationForm(
            applicationFormId: "sample-application-form-sf424",
            formId: sf424.formId,
            form: sf424,
            applicationResponse: .object(["applicant_name": .string("Civic Resilience Collaborative")]),
            isRequired: true,
            applicationId: applicationId
        ),
        ApplicationForm(
            applicationFormId: "sample-application-form-sf424a",
            formId: sf424A.formId,
            form: sf424A,
            isRequired: true,
            applicationId: applicationId
        ),
        ApplicationForm(
            applicationFormId: "sample-application-form-sf424b",
            formId: sf424B.formId,
            form: sf424B,
            isRequired: true,
            applicationId: applicationId
        )
    ]

    static let application = Application(
        applicationId: applicationId,
        applicationName: "Community Health Resilience — Draft",
        applicationStatus: "in_progress",
        competition: openCompetition,
        organization: organization,
        applicationForms: applicationForms
    )

    static let applicationSummary = ApplicationSummary(
        applicationId: applicationId,
        applicationName: application.applicationName,
        applicationStatus: application.applicationStatus,
        organization: organization,
        competition: ApplicationCompetition(
            competitionId: openCompetition.competitionId,
            competitionTitle: openCompetition.competitionTitle,
            openingDate: openCompetition.openingDate,
            closingDate: openCompetition.closingDate,
            isOpen: openCompetition.isOpen,
            opportunity: ApplicationOpportunity(
                opportunityId: posted.opportunityId,
                opportunityTitle: posted.opportunityTitle,
                agencyName: posted.agencyName
            )
        )
    )
}

public actor PreviewDataSource: GrantsDataSource {
    private var application = PreviewFixtures.application
    private var savedIds: Set<String> = [PreviewFixtures.posted.opportunityId]

    public init() {}

    public func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        let query = request.query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = PreviewFixtures.opportunities.filter { opportunity in
            let matchesQuery = query.map {
                $0.isEmpty
                    || (opportunity.opportunityTitle?.lowercased().contains($0) ?? false)
                    || (opportunity.summary.summaryDescription?.lowercased().contains($0) ?? false)
            } ?? true
            let matchesStatus = request.filters.opportunityStatus.isEmpty
                || request.filters.opportunityStatus.contains(opportunity.opportunityStatus.rawValue)
            return matchesQuery && matchesStatus
        }
        let pageSize = max(1, request.pagination.pageSize)
        let start = max(0, request.pagination.pageOffset - 1) * pageSize
        let page = Array(matches.dropFirst(start).prefix(pageSize))
        let counts = Dictionary(grouping: matches, by: { $0.opportunityStatus.rawValue })
            .mapValues { $0.count }
        return SearchResponse(
            data: page,
            paginationInfo: PaginationInfo(
                pageOffset: request.pagination.pageOffset,
                pageSize: pageSize,
                totalPages: max(1, Int(ceil(Double(matches.count) / Double(pageSize)))),
                totalRecords: matches.count
            ),
            facetCounts: ["opportunity_status": counts]
        )
    }

    public func opportunity(id: String) async throws -> OpportunityDetail {
        guard let detail = PreviewFixtures.details.first(where: { $0.opportunityId == id }) else {
            throw GrantsError.notFound
        }
        return detail
    }

    public func currentUser() async throws -> UserProfile {
        UserProfile(
            userId: "sample-dana-reyes",
            email: "dana.reyes@example.org",
            firstName: "Dana",
            lastName: "Reyes"
        )
    }

    public func organizations() async throws -> [Organization] {
        [PreviewFixtures.organization]
    }

    public func applications() async throws -> [ApplicationSummary] {
        [PreviewFixtures.applicationSummary]
    }

    public func startApplication(
        competitionId: String,
        name: String,
        organizationId: String?
    ) async throws -> String {
        guard competitionId == PreviewFixtures.openCompetition.competitionId else {
            throw GrantsError.notFound
        }
        return PreviewFixtures.applicationId
    }

    public func application(id: String) async throws -> Application {
        guard id == application.applicationId else { throw GrantsError.notFound }
        return application
    }

    public func form(id: String) async throws -> FormDefinition {
        guard let form = PreviewFixtures.openCompetition.competitionForms.first(where: { $0.form.formId == id })?.form else {
            throw GrantsError.notFound
        }
        return form
    }

    public func saveForm(
        applicationId: String,
        formId: String,
        response: JSONValue
    ) async throws -> FormSaveResult {
        guard applicationId == application.applicationId,
              let existing = application.applicationForms.first(where: { $0.formId == formId })
        else {
            throw GrantsError.notFound
        }
        let updated = ApplicationForm(
            applicationFormId: existing.applicationFormId,
            formId: existing.formId,
            form: existing.form,
            applicationResponse: response,
            applicationFormStatus: "in_progress",
            isRequired: existing.isRequired,
            isIncludedInSubmission: existing.isIncludedInSubmission,
            applicationId: existing.applicationId,
            applicationName: existing.applicationName
        )
        let forms = application.applicationForms.map { $0.formId == formId ? updated : $0 }
        application = Application(
            applicationId: application.applicationId,
            applicationName: application.applicationName,
            applicationStatus: application.applicationStatus,
            competition: application.competition,
            organization: application.organization,
            applicationForms: forms,
            formValidationWarnings: application.formValidationWarnings,
            intendsToAddOrganization: application.intendsToAddOrganization
        )
        return FormSaveResult(form: updated)
    }

    public func submit(applicationId: String) async throws -> SubmissionResult {
        guard applicationId == application.applicationId else { throw GrantsError.notFound }
        return SubmissionResult(applicationId: applicationId, trackingNumber: "DEMO-2027-0001")
    }

    public func savedOpportunityIds() async throws -> Set<String> {
        savedIds
    }

    public func setSaved(_ saved: Bool, opportunityId: String) async throws {
        if saved {
            savedIds.insert(opportunityId)
        } else {
            savedIds.remove(opportunityId)
        }
    }
}
