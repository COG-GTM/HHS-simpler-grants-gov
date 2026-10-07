import Foundation

public enum OpportunityStatus: String, Codable, Sendable, CaseIterable {
    case forecasted
    case posted
    case closed
    case archived
}

public struct Opportunity: Codable, Sendable, Hashable, Identifiable {
    public let opportunityId: String
    public let opportunityNumber: String?
    public let opportunityTitle: String?
    public let agencyCode: String?
    public let agencyName: String?
    public let topLevelAgencyName: String?
    public let category: String?
    public let opportunityStatus: OpportunityStatus
    public let summary: OpportunitySummary
    public let opportunityAssistanceListings: [OpportunityAssistanceListing]
    public let tagline: String?
    public let agency: String?
    public let topLevelAgencyCode: String?
    public let categoryExplanation: String?
    public let purposeStatement: String?
    public let legacyOpportunityId: Int?

    public var id: String { opportunityId }

    public init(
        opportunityId: String,
        opportunityNumber: String? = nil,
        opportunityTitle: String? = nil,
        agencyCode: String? = nil,
        agencyName: String? = nil,
        topLevelAgencyName: String? = nil,
        category: String? = nil,
        opportunityStatus: OpportunityStatus,
        summary: OpportunitySummary,
        opportunityAssistanceListings: [OpportunityAssistanceListing] = [],
        tagline: String? = nil,
        agency: String? = nil,
        topLevelAgencyCode: String? = nil,
        categoryExplanation: String? = nil,
        purposeStatement: String? = nil,
        legacyOpportunityId: Int? = nil
    ) {
        self.opportunityId = opportunityId
        self.opportunityNumber = opportunityNumber
        self.opportunityTitle = opportunityTitle
        self.agencyCode = agencyCode
        self.agencyName = agencyName
        self.topLevelAgencyName = topLevelAgencyName
        self.category = category
        self.opportunityStatus = opportunityStatus
        self.summary = summary
        self.opportunityAssistanceListings = opportunityAssistanceListings
        self.tagline = tagline
        self.agency = agency
        self.topLevelAgencyCode = topLevelAgencyCode
        self.categoryExplanation = categoryExplanation
        self.purposeStatement = purposeStatement
        self.legacyOpportunityId = legacyOpportunityId
    }
}

public struct OpportunitySummary: Codable, Sendable, Hashable {
    public let summaryDescription: String?
    public let isCostSharing: Bool?
    public let closeDate: String?
    public let postDate: String?
    public let archiveDate: String?
    public let forecastedCloseDate: String?
    public let forecastedPostDate: String?
    public let forecastedAwardDate: String?
    public let forecastedProjectStartDate: String?
    public let forecastedCloseDateDescription: String?
    public let closeDateDescription: String?
    public let awardFloor: Int?
    public let awardCeiling: Int?
    public let estimatedTotalProgramFunding: Int?
    public let expectedNumberOfAwards: Int?
    public let fiscalYear: Int?
    public let applicantTypes: [String]?
    public let fundingCategories: [String]?
    public let fundingInstruments: [String]?
    public let applicantEligibilityDescription: String?
    public let agencyContactDescription: String?
    public let agencyEmailAddress: String?
    public let additionalInfoUrl: String?
    public let additionalInfoUrlDescription: String?
    public let fundingCategoryDescription: String?
    public let isForecast: Bool?
    public let versionNumber: Int?

    public init(
        summaryDescription: String? = nil,
        isCostSharing: Bool? = nil,
        closeDate: String? = nil,
        postDate: String? = nil,
        archiveDate: String? = nil,
        forecastedCloseDate: String? = nil,
        forecastedPostDate: String? = nil,
        forecastedAwardDate: String? = nil,
        forecastedProjectStartDate: String? = nil,
        forecastedCloseDateDescription: String? = nil,
        closeDateDescription: String? = nil,
        awardFloor: Int? = nil,
        awardCeiling: Int? = nil,
        estimatedTotalProgramFunding: Int? = nil,
        expectedNumberOfAwards: Int? = nil,
        fiscalYear: Int? = nil,
        applicantTypes: [String]? = nil,
        fundingCategories: [String]? = nil,
        fundingInstruments: [String]? = nil,
        applicantEligibilityDescription: String? = nil,
        agencyContactDescription: String? = nil,
        agencyEmailAddress: String? = nil,
        additionalInfoUrl: String? = nil,
        additionalInfoUrlDescription: String? = nil,
        fundingCategoryDescription: String? = nil,
        isForecast: Bool? = nil,
        versionNumber: Int? = nil
    ) {
        self.summaryDescription = summaryDescription
        self.isCostSharing = isCostSharing
        self.closeDate = closeDate
        self.postDate = postDate
        self.archiveDate = archiveDate
        self.forecastedCloseDate = forecastedCloseDate
        self.forecastedPostDate = forecastedPostDate
        self.forecastedAwardDate = forecastedAwardDate
        self.forecastedProjectStartDate = forecastedProjectStartDate
        self.forecastedCloseDateDescription = forecastedCloseDateDescription
        self.closeDateDescription = closeDateDescription
        self.awardFloor = awardFloor
        self.awardCeiling = awardCeiling
        self.estimatedTotalProgramFunding = estimatedTotalProgramFunding
        self.expectedNumberOfAwards = expectedNumberOfAwards
        self.fiscalYear = fiscalYear
        self.applicantTypes = applicantTypes
        self.fundingCategories = fundingCategories
        self.fundingInstruments = fundingInstruments
        self.applicantEligibilityDescription = applicantEligibilityDescription
        self.agencyContactDescription = agencyContactDescription
        self.agencyEmailAddress = agencyEmailAddress
        self.additionalInfoUrl = additionalInfoUrl
        self.additionalInfoUrlDescription = additionalInfoUrlDescription
        self.fundingCategoryDescription = fundingCategoryDescription
        self.isForecast = isForecast
        self.versionNumber = versionNumber
    }

    public var closeDateValue: Date? { Self.date(from: closeDate) }
    public var postDateValue: Date? { Self.date(from: postDate) }
    public var archiveDateValue: Date? { Self.date(from: archiveDate) }
    public var forecastedCloseDateValue: Date? { Self.date(from: forecastedCloseDate) }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

public struct OpportunityAssistanceListing: Codable, Sendable, Hashable, Identifiable {
    public let assistanceListingNumber: String?
    public let programTitle: String?

    public var id: String { assistanceListingNumber ?? programTitle ?? "" }

    public init(assistanceListingNumber: String? = nil, programTitle: String? = nil) {
        self.assistanceListingNumber = assistanceListingNumber
        self.programTitle = programTitle
    }
}

public struct OpportunityAttachment: Codable, Sendable, Hashable, Identifiable {
    public let opportunityAttachmentId: String?
    public let fileName: String?
    public let fileType: String?
    public let downloadPath: String?
    public let mimeType: String?

    public var id: String { opportunityAttachmentId ?? fileName ?? "" }

    public init(
        opportunityAttachmentId: String? = nil,
        fileName: String? = nil,
        fileType: String? = nil,
        downloadPath: String? = nil,
        mimeType: String? = nil
    ) {
        self.opportunityAttachmentId = opportunityAttachmentId
        self.fileName = fileName
        self.fileType = fileType
        self.downloadPath = downloadPath
        self.mimeType = mimeType
    }
}

public struct OpportunityDetail: Codable, Sendable, Hashable, Identifiable {
    public let opportunity: Opportunity
    public let attachments: [OpportunityAttachment]
    public let competitions: [Competition]

    public var id: String { opportunity.opportunityId }
    public var opportunityId: String { opportunity.opportunityId }
    public var opportunityNumber: String? { opportunity.opportunityNumber }
    public var opportunityTitle: String? { opportunity.opportunityTitle }
    public var agencyCode: String? { opportunity.agencyCode }
    public var agencyName: String? { opportunity.agencyName }
    public var topLevelAgencyName: String? { opportunity.topLevelAgencyName }
    public var category: String? { opportunity.category }
    public var opportunityStatus: OpportunityStatus { opportunity.opportunityStatus }
    public var summary: OpportunitySummary { opportunity.summary }
    public var opportunityAssistanceListings: [OpportunityAssistanceListing] {
        opportunity.opportunityAssistanceListings
    }

    public init(
        opportunity: Opportunity,
        attachments: [OpportunityAttachment] = [],
        competitions: [Competition] = []
    ) {
        self.opportunity = opportunity
        self.attachments = attachments
        self.competitions = competitions
    }

    private enum CodingKeys: String, CodingKey {
        case opportunityId
        case opportunityNumber
        case opportunityTitle
        case agencyCode
        case agencyName
        case topLevelAgencyName
        case category
        case opportunityStatus
        case summary
        case opportunityAssistanceListings
        case tagline
        case agency
        case topLevelAgencyCode
        case categoryExplanation
        case purposeStatement
        case legacyOpportunityId
        case attachments
        case competitions
    }

    public init(from decoder: Decoder) throws {
        opportunity = try Opportunity(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attachments = try container.decodeIfPresent([OpportunityAttachment].self, forKey: .attachments) ?? []
        competitions = try container.decodeIfPresent([Competition].self, forKey: .competitions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(opportunity.opportunityId, forKey: .opportunityId)
        try container.encodeIfPresent(opportunity.opportunityNumber, forKey: .opportunityNumber)
        try container.encodeIfPresent(opportunity.opportunityTitle, forKey: .opportunityTitle)
        try container.encodeIfPresent(opportunity.agencyCode, forKey: .agencyCode)
        try container.encodeIfPresent(opportunity.agencyName, forKey: .agencyName)
        try container.encodeIfPresent(opportunity.topLevelAgencyName, forKey: .topLevelAgencyName)
        try container.encodeIfPresent(opportunity.category, forKey: .category)
        try container.encode(opportunity.opportunityStatus, forKey: .opportunityStatus)
        try container.encode(opportunity.summary, forKey: .summary)
        try container.encode(opportunity.opportunityAssistanceListings, forKey: .opportunityAssistanceListings)
        try container.encodeIfPresent(opportunity.tagline, forKey: .tagline)
        try container.encodeIfPresent(opportunity.agency, forKey: .agency)
        try container.encodeIfPresent(opportunity.topLevelAgencyCode, forKey: .topLevelAgencyCode)
        try container.encodeIfPresent(opportunity.categoryExplanation, forKey: .categoryExplanation)
        try container.encodeIfPresent(opportunity.purposeStatement, forKey: .purposeStatement)
        try container.encodeIfPresent(opportunity.legacyOpportunityId, forKey: .legacyOpportunityId)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(competitions, forKey: .competitions)
    }
}

public struct Competition: Codable, Sendable, Hashable, Identifiable {
    public let competitionId: String
    public let competitionTitle: String?
    public let openingDate: String?
    public let closingDate: String?
    public let isOpen: Bool
    public let isSimplerGrantsEnabled: Bool
    public let openToApplicants: [String]
    public let competitionForms: [CompetitionForm]
    public let opportunityId: String?
    public let publicCompetitionId: String?
    public let contactInfo: String?
    public let gracePeriod: Int?
    public let opportunityAssistanceListing: OpportunityAssistanceListing?
    public let competitionInstructions: [CompetitionInstruction]

    public var id: String { competitionId }

    public init(
        competitionId: String,
        competitionTitle: String? = nil,
        openingDate: String? = nil,
        closingDate: String? = nil,
        isOpen: Bool,
        isSimplerGrantsEnabled: Bool,
        openToApplicants: [String] = [],
        competitionForms: [CompetitionForm] = [],
        opportunityId: String? = nil,
        publicCompetitionId: String? = nil,
        contactInfo: String? = nil,
        gracePeriod: Int? = nil,
        opportunityAssistanceListing: OpportunityAssistanceListing? = nil,
        competitionInstructions: [CompetitionInstruction] = []
    ) {
        self.competitionId = competitionId
        self.competitionTitle = competitionTitle
        self.openingDate = openingDate
        self.closingDate = closingDate
        self.isOpen = isOpen
        self.isSimplerGrantsEnabled = isSimplerGrantsEnabled
        self.openToApplicants = openToApplicants
        self.competitionForms = competitionForms
        self.opportunityId = opportunityId
        self.publicCompetitionId = publicCompetitionId
        self.contactInfo = contactInfo
        self.gracePeriod = gracePeriod
        self.opportunityAssistanceListing = opportunityAssistanceListing
        self.competitionInstructions = competitionInstructions
    }
}

public struct CompetitionForm: Codable, Sendable, Hashable, Identifiable {
    public let isRequired: Bool
    public let form: FormDefinition

    public var id: String { form.formId }

    public init(isRequired: Bool, form: FormDefinition) {
        self.isRequired = isRequired
        self.form = form
    }
}

public struct CompetitionInstruction: Codable, Sendable, Hashable, Identifiable {
    public let competitionInstructionId: String?
    public let fileName: String?
    public let downloadPath: String?

    public var id: String { competitionInstructionId ?? fileName ?? "" }

    public init(
        competitionInstructionId: String? = nil,
        fileName: String? = nil,
        downloadPath: String? = nil
    ) {
        self.competitionInstructionId = competitionInstructionId
        self.fileName = fileName
        self.downloadPath = downloadPath
    }
}

public struct FormDefinition: Codable, Sendable, Hashable, Identifiable {
    public let formId: String
    public let formName: String?
    public let shortFormName: String?
    public let formVersion: String?
    public let formType: String?
    public let formJsonSchema: JSONValue
    public let formUiSchema: JSONValue
    public let formRuleSchema: JSONValue?
    public let agencyCode: String?
    public let ombNumber: String?

    public var id: String { formId }

    public init(
        formId: String,
        formName: String? = nil,
        shortFormName: String? = nil,
        formVersion: String? = nil,
        formType: String? = nil,
        formJsonSchema: JSONValue = .object([:]),
        formUiSchema: JSONValue = .array([]),
        formRuleSchema: JSONValue? = nil,
        agencyCode: String? = nil,
        ombNumber: String? = nil
    ) {
        self.formId = formId
        self.formName = formName
        self.shortFormName = shortFormName
        self.formVersion = formVersion
        self.formType = formType
        self.formJsonSchema = formJsonSchema
        self.formUiSchema = formUiSchema
        self.formRuleSchema = formRuleSchema
        self.agencyCode = agencyCode
        self.ombNumber = ombNumber
    }
}

public struct UserProfile: Codable, Sendable, Hashable, Identifiable {
    public let userId: String
    public let email: String
    public let firstName: String?
    public let lastName: String?

    public var id: String { userId }

    public init(userId: String, email: String, firstName: String? = nil, lastName: String? = nil) {
        self.userId = userId
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
    }

    private enum CodingKeys: String, CodingKey {
        case userId
        case email
        case firstName
        case lastName
        case profile
    }

    private struct Profile: Decodable {
        let firstName: String?
        let lastName: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let profile = try container.decodeIfPresent(Profile.self, forKey: .profile)
        userId = try container.decode(String.self, forKey: .userId)
        email = try container.decode(String.self, forKey: .email)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? profile?.firstName
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? profile?.lastName
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(lastName, forKey: .lastName)
    }
}

public struct SamGovEntity: Codable, Sendable, Hashable {
    public let uei: String?
    public let legalBusinessName: String?
    public let expirationDate: String?
    public let ebizPocEmail: String?
    public let ebizPocFirstName: String?
    public let ebizPocLastName: String?

    public init(
        uei: String? = nil,
        legalBusinessName: String? = nil,
        expirationDate: String? = nil,
        ebizPocEmail: String? = nil,
        ebizPocFirstName: String? = nil,
        ebizPocLastName: String? = nil
    ) {
        self.uei = uei
        self.legalBusinessName = legalBusinessName
        self.expirationDate = expirationDate
        self.ebizPocEmail = ebizPocEmail
        self.ebizPocFirstName = ebizPocFirstName
        self.ebizPocLastName = ebizPocLastName
    }
}

public struct Organization: Codable, Sendable, Hashable, Identifiable {
    public let organizationId: String
    public let samGovEntity: SamGovEntity?

    public var id: String { organizationId }

    public init(organizationId: String, samGovEntity: SamGovEntity? = nil) {
        self.organizationId = organizationId
        self.samGovEntity = samGovEntity
    }
}

public struct ApplicationOpportunity: Codable, Sendable, Hashable, Identifiable {
    public let opportunityId: String
    public let opportunityTitle: String?
    public let agencyName: String?

    public var id: String { opportunityId }

    public init(opportunityId: String, opportunityTitle: String? = nil, agencyName: String? = nil) {
        self.opportunityId = opportunityId
        self.opportunityTitle = opportunityTitle
        self.agencyName = agencyName
    }
}

public struct ApplicationCompetition: Codable, Sendable, Hashable, Identifiable {
    public let competitionId: String
    public let competitionTitle: String?
    public let openingDate: String?
    public let closingDate: String?
    public let isOpen: Bool
    public let opportunity: ApplicationOpportunity

    public var id: String { competitionId }

    public init(
        competitionId: String,
        competitionTitle: String? = nil,
        openingDate: String? = nil,
        closingDate: String? = nil,
        isOpen: Bool,
        opportunity: ApplicationOpportunity
    ) {
        self.competitionId = competitionId
        self.competitionTitle = competitionTitle
        self.openingDate = openingDate
        self.closingDate = closingDate
        self.isOpen = isOpen
        self.opportunity = opportunity
    }
}

public struct ApplicationSummary: Codable, Sendable, Hashable, Identifiable {
    public let applicationId: String
    public let applicationName: String?
    public let applicationStatus: String
    public let organization: Organization?
    public let competition: ApplicationCompetition

    public var id: String { applicationId }

    public init(
        applicationId: String,
        applicationName: String? = nil,
        applicationStatus: String,
        organization: Organization? = nil,
        competition: ApplicationCompetition
    ) {
        self.applicationId = applicationId
        self.applicationName = applicationName
        self.applicationStatus = applicationStatus
        self.organization = organization
        self.competition = competition
    }
}

public struct ApplicationForm: Codable, Sendable, Hashable, Identifiable {
    public let applicationFormId: String
    public let formId: String
    public let form: FormDefinition
    public let applicationResponse: JSONValue
    public let applicationFormStatus: String
    public let isRequired: Bool
    public let isIncludedInSubmission: Bool?
    public let applicationId: String?
    public let applicationName: String?

    public var id: String { applicationFormId }

    public init(
        applicationFormId: String,
        formId: String,
        form: FormDefinition,
        applicationResponse: JSONValue = .object([:]),
        applicationFormStatus: String = "in_progress",
        isRequired: Bool,
        isIncludedInSubmission: Bool? = true,
        applicationId: String? = nil,
        applicationName: String? = nil
    ) {
        self.applicationFormId = applicationFormId
        self.formId = formId
        self.form = form
        self.applicationResponse = applicationResponse
        self.applicationFormStatus = applicationFormStatus
        self.isRequired = isRequired
        self.isIncludedInSubmission = isIncludedInSubmission
        self.applicationId = applicationId
        self.applicationName = applicationName
    }
}

public struct Application: Codable, Sendable, Hashable, Identifiable {
    public let applicationId: String
    public let applicationName: String
    public let applicationStatus: String
    public let competition: Competition
    public let organization: Organization?
    public let applicationForms: [ApplicationForm]
    public let formValidationWarnings: JSONValue
    public let intendsToAddOrganization: Bool?

    public var id: String { applicationId }

    public init(
        applicationId: String,
        applicationName: String,
        applicationStatus: String,
        competition: Competition,
        organization: Organization? = nil,
        applicationForms: [ApplicationForm] = [],
        formValidationWarnings: JSONValue = .object([:]),
        intendsToAddOrganization: Bool? = nil
    ) {
        self.applicationId = applicationId
        self.applicationName = applicationName
        self.applicationStatus = applicationStatus
        self.competition = competition
        self.organization = organization
        self.applicationForms = applicationForms
        self.formValidationWarnings = formValidationWarnings
        self.intendsToAddOrganization = intendsToAddOrganization
    }
}

public struct ValidationWarning: Codable, Sendable, Hashable {
    public let field: String
    public let message: String
    public let type: String
    public let value: JSONValue?

    public init(field: String, message: String, type: String, value: JSONValue? = nil) {
        self.field = field
        self.message = message
        self.type = type
        self.value = value
    }
}

public struct FormSaveResult: Codable, Sendable, Hashable {
    public let warnings: [ValidationWarning]
    public let form: ApplicationForm

    public init(warnings: [ValidationWarning] = [], form: ApplicationForm) {
        self.warnings = warnings
        self.form = form
    }
}

public struct SubmissionResult: Codable, Sendable, Hashable {
    public let applicationId: String
    public let trackingNumber: String?

    public init(applicationId: String, trackingNumber: String? = nil) {
        self.applicationId = applicationId
        self.trackingNumber = trackingNumber
    }

    private enum CodingKeys: String, CodingKey {
        case applicationId
        case trackingNumber
        case legacyTrackingNumber
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applicationId = try container.decode(String.self, forKey: .applicationId)
        trackingNumber = try container.decodeIfPresent(String.self, forKey: .trackingNumber)
            ?? container.decodeIfPresent(String.self, forKey: .legacyTrackingNumber)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(applicationId, forKey: .applicationId)
        try container.encodeIfPresent(trackingNumber, forKey: .legacyTrackingNumber)
    }
}
