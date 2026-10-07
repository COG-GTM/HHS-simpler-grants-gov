import Foundation
import SGModels

public struct SampleDataSource: GrantsDataSource {
    private let details: [OpportunityDetail]
    private let forms: [String: FormDefinition]
    private let organization: Organization
    private let store: SampleStore
    private let latency: Duration
    private let referenceDate: Date

    public init(referenceDate: Date = Date(), latency: Duration = .milliseconds(150)) {
        let referenceDay = Calendar.sampleUTC.startOfDay(for: referenceDate)
        let formCatalog = Self.loadForms()
        let loaded = Self.loadOpportunities(referenceDate: referenceDay, forms: formCatalog)
        let sampleOrganization = Self.makeOrganization(referenceDate: referenceDay)
        details = loaded
        forms = formCatalog
        organization = sampleOrganization
        store = SampleStore(details: loaded, organization: sampleOrganization)
        self.latency = latency
        self.referenceDate = referenceDay
    }

    public func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        try await waitForLatency()
        return Self.search(request, in: details, referenceDate: referenceDate)
    }

    public func opportunity(id: String) async throws -> OpportunityDetail {
        try await waitForLatency()
        guard let detail = details.first(where: { $0.opportunityId == id }) else {
            throw GrantsError.notFound
        }
        return detail
    }

    public func currentUser() async throws -> UserProfile {
        try await waitForLatency()
        return SampleUser.profile
    }

    public func organizations() async throws -> [Organization] {
        try await waitForLatency()
        return [organization]
    }

    public func applications() async throws -> [ApplicationSummary] {
        try await waitForLatency()
        return await store.applications()
    }

    public func startApplication(
        competitionId: String,
        name: String,
        organizationId: String?
    ) async throws -> String {
        try await waitForLatency()
        guard let detail = details.first(where: { $0.competitions.contains(where: { $0.competitionId == competitionId }) }),
              let competition = detail.competitions.first(where: { $0.competitionId == competitionId })
        else {
            throw GrantsError.notFound
        }
        guard organizationId == nil || organizationId == organization.organizationId else {
            throw GrantsError.notFound
        }
        guard competition.isOpen, competition.isSimplerGrantsEnabled else {
            throw GrantsError.server(status: 422, message: "This competition is not available in the sample application.")
        }
        return await store.startApplication(
            competition: competition,
            opportunity: detail.opportunity,
            name: name,
            organization: organizationId == nil ? nil : organization
        )
    }

    public func application(id: String) async throws -> Application {
        try await waitForLatency()
        return try await store.application(id: id)
    }

    public func form(id: String) async throws -> FormDefinition {
        try await waitForLatency()
        guard let form = forms[id] else { throw GrantsError.notFound }
        return form
    }

    public func saveForm(
        applicationId: String,
        formId: String,
        response: JSONValue
    ) async throws -> FormSaveResult {
        try await waitForLatency()
        return try await store.saveForm(applicationId: applicationId, formId: formId, response: response)
    }

    public func submit(applicationId: String) async throws -> SubmissionResult {
        try await waitForLatency()
        return try await store.submit(applicationId: applicationId)
    }

    public func savedOpportunityIds() async throws -> Set<String> {
        try await waitForLatency()
        return await store.savedOpportunityIds()
    }

    public func setSaved(_ saved: Bool, opportunityId: String) async throws {
        try await waitForLatency()
        await store.setSaved(saved, opportunityId: opportunityId)
    }

    private func waitForLatency() async throws {
        if latency > .zero {
            try await Task.sleep(for: latency)
        }
    }

    private static func loadOpportunities(
        referenceDate: Date,
        forms: [String: FormDefinition]
    ) -> [OpportunityDetail] {
        do {
            guard let url = Bundle.module.url(forResource: "opportunities", withExtension: "json", subdirectory: "Data") else {
                fatalError("SGSampleData is missing Resources/Data/opportunities.json")
            }
            let data = try Data(contentsOf: url)
            guard case let .object(root) = try JSONDecoder().decode(JSONValue.self, from: data),
                  case let .string(anchorString)? = root["anchor_date"],
                  case let .array(opportunities)? = root["opportunities"],
                  let anchor = dateFormatter.date(from: anchorString)
            else {
                fatalError("SGSampleData could not decode the opportunities resource envelope")
            }
            let dayOffset = Calendar.sampleUTC.dateComponents([.day], from: anchor, to: referenceDate).day ?? 0
            let today = dateFormatter.string(from: referenceDate)
            let transformed = opportunities.map {
                shiftAndHydrate($0, dayOffset: dayOffset, today: today, forms: forms)
            }
            let json = JSONValue.array(transformed)
            let encoded = try JSONEncoder().encode(json)
            return try JSONDecoder.sg.decode([OpportunityDetail].self, from: encoded)
        } catch {
            fatalError("SGSampleData could not load opportunity sample data: \(error)")
        }
    }

    private static func shiftAndHydrate(
        _ value: JSONValue,
        dayOffset: Int,
        today: String,
        forms: [String: FormDefinition]
    ) -> JSONValue {
        guard case let .object(opportunity) = value else { return value }
        let dateKeys: Set<String> = [
            "post_date", "close_date", "archive_date", "forecasted_post_date", "forecasted_close_date",
            "forecasted_award_date", "forecasted_project_start_date", "opening_date", "closing_date"
        ]
        func shiftDates(_ value: JSONValue) -> JSONValue {
            switch value {
            case let .object(object):
                return .object(object.reduce(into: [:]) { result, pair in
                    if dateKeys.contains(pair.key), case let .string(dateString) = pair.value,
                       let date = dateFormatter.date(from: dateString),
                       let adjusted = Calendar.sampleUTC.date(byAdding: .day, value: dayOffset, to: date) {
                        result[pair.key] = .string(dateFormatter.string(from: adjusted))
                    } else {
                        result[pair.key] = shiftDates(pair.value)
                    }
                })
            case let .array(array):
                return .array(array.map(shiftDates))
            default:
                return value
            }
        }
        guard case var .object(shifted) = shiftDates(.object(opportunity)),
              case let .object(summary) = shifted["summary"]
        else { return value }
        let forecast: Bool
        if case let .bool(value)? = summary["is_forecast"] { forecast = value } else { forecast = false }
        let archiveDate = string(summary["archive_date"])
        let closeDate = string(summary["close_date"])
        let status: String
        if forecast {
            status = "forecasted"
        } else if let archiveDate, archiveDate <= today {
            status = "archived"
        } else if let closeDate, closeDate < today {
            status = "closed"
        } else {
            status = "posted"
        }
        shifted["opportunity_status"] = .string(status)
        shifted["summary"] = .object(summary)
        if case let .array(competitions)? = shifted["competitions"] {
            shifted["competitions"] = .array(competitions.map { competitionValue in
                guard case var .object(competition) = competitionValue else { return competitionValue }
                let opening = string(competition["opening_date"])
                let closing = string(competition["closing_date"])
                competition["is_open"] = .bool(
                    status == "posted"
                        && opening.map { $0 <= today } == true
                        && closing.map { today <= $0 } == true
                )
                if case let .array(samples)? = competition["sample_forms"] {
                    let competitionForms = samples.map { sample -> JSONValue in
                        guard case let .object(sampleObject) = sample,
                              let formId = string(sampleObject["form_id"])
                        else {
                            fatalError("SGSampleData found an invalid sample form entry")
                        }
                        guard let form = forms[formId] else {
                            fatalError("SGSampleData references missing form \(formId)")
                        }
                        let isRequired: Bool
                        if case let .bool(value)? = sampleObject["is_required"] { isRequired = value } else { isRequired = true }
                        return .object(["is_required": .bool(isRequired), "form": formValue(form)])
                    }
                    competition["competition_forms"] = .array(competitionForms)
                    competition.removeValue(forKey: "sample_forms")
                }
                return .object(competition)
            })
        }
        return .object(shifted)
    }

    private static func formValue(_ form: FormDefinition) -> JSONValue {
        guard let data = try? JSONEncoder().encode(form),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            fatalError("SGSampleData could not encode form \(form.formId)")
        }
        return value
    }

    private static func loadForms() -> [String: FormDefinition] {
        let names = ["sf424", "sf424a", "sf424b", "project_narrative_attachment", "sflll", "project_performance_site_location"]
        do {
            return try names.reduce(into: [:]) { result, name in
                guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Forms") else {
                    fatalError("SGSampleData is missing Resources/Forms/\(name).json")
                }
                let form = try JSONDecoder.sg.decode(FormDefinition.self, from: Data(contentsOf: url))
                result[form.formId] = form
            }
        } catch {
            fatalError("SGSampleData could not load bundled form definitions: \(error)")
        }
    }

    private static func makeOrganization(referenceDate: Date) -> Organization {
        let expiration = Calendar.sampleUTC.date(byAdding: .month, value: 8, to: referenceDate) ?? referenceDate
        return Organization(
            organizationId: "sample-bluefield-community-health-center",
            samGovEntity: SamGovEntity(
                uei: "K7LMN2QX4R91",
                legalBusinessName: "Bluefield Community Health Center",
                expirationDate: dateFormatter.string(from: expiration),
                ebizPocEmail: SampleUser.profile.email,
                ebizPocFirstName: "Dana",
                ebizPocLastName: "Reyes"
            )
        )
    }

    private static func search(
        _ request: SearchRequest,
        in details: [OpportunityDetail],
        referenceDate: Date
    ) -> SearchResponse {
        let query = tokens(request.query)
        let operatorName = request.queryOperator.uppercased()
        let matches = details.compactMap { detail -> (Opportunity, Int)? in
            let opportunity = detail.opportunity
            let score = relevanceScore(query, opportunity: opportunity)
            if !query.isEmpty {
                let isMatch = operatorName == "OR"
                    ? score > 0
                    : queryContainsAll(query, opportunity: opportunity)
                if !isMatch { return nil }
            }
            guard matchesFilters(opportunity, filters: request.filters) else { return nil }
            return (opportunity, score)
        }
        let sort = request.pagination.sortOrder.first
        let orderBy = sort?.orderBy ?? (query.isEmpty ? "post_date" : "relevancy")
        let ascending = sort?.sortDirection.lowercased() == "ascending"
        let sorted = matches.sorted { lhs, rhs in
            if orderBy.lowercased() == "relevancy", lhs.1 != rhs.1 {
                return ascending ? lhs.1 < rhs.1 : lhs.1 > rhs.1
            }
            let lhsMissing = sortValueIsMissing(lhs.0, orderBy: orderBy)
            let rhsMissing = sortValueIsMissing(rhs.0, orderBy: orderBy)
            if lhsMissing != rhsMissing { return !lhsMissing }
            let comparison = compare(lhs.0, rhs.0, orderBy: orderBy)
            if comparison != 0 { return ascending ? comparison < 0 : comparison > 0 }
            return (lhs.0.opportunityNumber ?? lhs.0.opportunityId)
                .localizedStandardCompare(rhs.0.opportunityNumber ?? rhs.0.opportunityId) == .orderedAscending
        }
        let pageSize = max(1, request.pagination.pageSize)
        let pageOffset = max(1, request.pagination.pageOffset)
        let start = (pageOffset - 1) * pageSize
        let page = start >= sorted.count ? [] : Array(sorted.dropFirst(start).prefix(pageSize))
        return SearchResponse(
            data: page.map(\.0),
            paginationInfo: PaginationInfo(
                pageOffset: pageOffset,
                pageSize: pageSize,
                sortOrder: request.pagination.sortOrder,
                totalPages: sorted.isEmpty ? 0 : Int(ceil(Double(sorted.count) / Double(pageSize))),
                totalRecords: sorted.count
            ),
            facetCounts: facetCounts(sorted.map(\.0), referenceDate: referenceDate)
        )
    }

    private static func matchesFilters(_ opportunity: Opportunity, filters: SearchFilters) -> Bool {
        func overlaps(_ selected: [String], _ values: [String]?) -> Bool {
            selected.isEmpty || !Set(selected).isDisjoint(with: values ?? [])
        }
        guard filters.opportunityStatus.isEmpty || filters.opportunityStatus.contains(opportunity.opportunityStatus.rawValue),
              overlaps(filters.applicantType, opportunity.summary.applicantTypes),
              overlaps(filters.fundingCategory, opportunity.summary.fundingCategories),
              overlaps(filters.fundingInstrument, opportunity.summary.fundingInstruments)
        else { return false }
        let agency = opportunity.agencyCode ?? ""
        return filters.agency.isEmpty || filters.agency.contains(where: {
            agency == $0 || agency.hasPrefix("\($0)-")
        })
    }

    private static func tokens(_ query: String?) -> [String] {
        let stopwords: Set<String> = ["a", "an", "the", "for", "my", "of", "and", "or", "to", "in", "with", "we", "run", "want", "our", "grants", "grant", "funding"]
        return (query ?? "")
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .map(stem)
            .filter { !$0.isEmpty && !stopwords.contains($0) }
    }

    private static func stem(_ token: String) -> String {
        if token.count > 5, token.hasSuffix("ies") { return String(token.dropLast(3)) + "y" }
        if token.count > 4, token.hasSuffix("s") { return String(token.dropLast()) }
        return token
    }

    private static func relevanceScore(_ query: [String], opportunity: Opportunity) -> Int {
        query.reduce(0) { total, term in
            total + fieldWeights(opportunity).reduce(0) { fieldTotal, field in
                fieldTotal + (field.tokens.contains(where: { $0 == term || $0.hasPrefix(term) || term.hasPrefix($0) }) ? field.weight : 0)
            }
        }
    }

    private static func queryContainsAll(_ query: [String], opportunity: Opportunity) -> Bool {
        let allTokens = fieldWeights(opportunity).flatMap(\.tokens)
        return query.allSatisfy { term in
            allTokens.contains(where: { $0 == term || $0.hasPrefix(term) || term.hasPrefix($0) })
        }
    }

    private static func fieldWeights(_ opportunity: Opportunity) -> [(tokens: [String], weight: Int)] {
        [
            (tokens(opportunity.opportunityTitle), 4),
            (tokens([opportunity.agencyName, opportunity.agencyCode].compactMap { $0 }.joined(separator: " ")), 3),
            (tokens(opportunity.summary.summaryDescription), 2),
            (tokens(opportunity.summary.applicantEligibilityDescription), 1)
        ]
    }

    private static func compare(_ lhs: Opportunity, _ rhs: Opportunity, orderBy: String) -> Int {
        let key = orderBy.lowercased()
        if key == "award_ceiling" || key == "awardceiling" {
            return compareOptional(lhs.summary.awardCeiling, rhs.summary.awardCeiling)
        }
        if key == "close_date" || key == "closedate" {
            return compareOptional(lhs.summary.closeDate, rhs.summary.closeDate)
        }
        if key == "opportunity_title" || key == "opportunitytitle" {
            return compareOptional(lhs.opportunityTitle, rhs.opportunityTitle)
        }
        if key == "opportunity_number" || key == "opportunitynumber" {
            return compareOptional(lhs.opportunityNumber, rhs.opportunityNumber)
        }
        if key == "agency_code" || key == "agencycode" {
            return compareOptional(lhs.agencyCode, rhs.agencyCode)
        }
        return compareOptional(lhs.summary.postDate, rhs.summary.postDate)
    }

    private static func sortValueIsMissing(_ opportunity: Opportunity, orderBy: String) -> Bool {
        let key = orderBy.lowercased()
        if key == "award_ceiling" || key == "awardceiling" { return opportunity.summary.awardCeiling == nil }
        if key == "close_date" || key == "closedate" { return opportunity.summary.closeDate == nil }
        if key == "opportunity_title" || key == "opportunitytitle" { return opportunity.opportunityTitle == nil }
        if key == "opportunity_number" || key == "opportunitynumber" { return opportunity.opportunityNumber == nil }
        if key == "agency_code" || key == "agencycode" { return opportunity.agencyCode == nil }
        return opportunity.summary.postDate == nil
    }

    private static func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> Int {
        switch (lhs, rhs) {
        case let (left?, right?): return left == right ? 0 : (left < right ? -1 : 1)
        case (nil, nil): return 0
        case (nil, _?): return 1
        case (_?, nil): return -1
        }
    }

    private static func facetCounts(_ opportunities: [Opportunity], referenceDate: Date) -> [String: [String: Int]] {
        var facets: [String: [String: Int]] = [
            "opportunity_status": [:], "applicant_type": [:], "funding_instrument": [:],
            "funding_category": [:], "agency": [:], "is_cost_sharing": [:],
            "close_date": [:], "post_date": [:]
        ]
        func count(_ key: String, _ value: String) {
            facets[key, default: [:]][value, default: 0] += 1
        }
        let today = Calendar.sampleUTC.startOfDay(for: referenceDate)
        for opportunity in opportunities {
            count("opportunity_status", opportunity.opportunityStatus.rawValue)
            for value in opportunity.summary.applicantTypes ?? [] { count("applicant_type", value) }
            for value in opportunity.summary.fundingInstruments ?? [] { count("funding_instrument", value) }
            for value in opportunity.summary.fundingCategories ?? [] { count("funding_category", value) }
            if let agency = opportunity.agencyCode { count("agency", agency) }
            if let sharing = opportunity.summary.isCostSharing { count("is_cost_sharing", sharing ? "true" : "false") }
            if let close = parseDate(opportunity.summary.closeDate), close >= today {
                let days = Calendar.sampleUTC.dateComponents([.day], from: today, to: close).day ?? Int.max
                for bucket in [7, 30, 60, 90, 120] where days <= bucket { count("close_date", String(bucket)) }
            }
            if opportunity.opportunityStatus == .posted,
               let post = parseDate(opportunity.summary.postDate), post <= today {
                let days = Calendar.sampleUTC.dateComponents([.day], from: post, to: today).day ?? Int.max
                for bucket in [3, 7, 14, 30, 60] where days <= bucket { count("post_date", String(bucket)) }
            }
        }
        return facets
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.sampleUTC
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return dateFormatter.date(from: value)
    }

    private static func string(_ value: JSONValue?) -> String? {
        guard case let .string(value) = value else { return nil }
        return value
    }
}

private extension Calendar {
    static let sampleUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()
}

private actor SampleStore {
    private let details: [OpportunityDetail]
    private let organization: Organization
    private var applicationsByID: [String: Application] = [:]
    private var savedIds: Set<String> = ["hrsa-27-014", "nea-27-02"]
    private var nextApplicationNumber = 2
    private var nextTrackingNumber = 14_102_836

    init(details: [OpportunityDetail], organization: Organization) {
        self.details = details
        self.organization = organization
        if let hrsa = details.first(where: { $0.opportunityId == "hrsa-27-014" }),
           let competition = hrsa.competitions.first {
            applicationsByID["sample-application-0001"] = Self.seedApplication(
                organization: organization,
                opportunity: hrsa.opportunity,
                competition: competition
            )
        }
    }

    func applications() -> [ApplicationSummary] {
        applicationsByID.values.sorted { $0.applicationId > $1.applicationId }.compactMap(summary(for:))
    }

    func startApplication(
        competition: Competition,
        opportunity: Opportunity,
        name: String,
        organization: Organization?
    ) -> String {
        let identifier = String(format: "sample-application-%04d", nextApplicationNumber)
        nextApplicationNumber += 1
        let applicationForms = competition.competitionForms.map { item in
            let response: JSONValue
            if item.form.formId == SampleFormIDs.sf424 {
                response = Self.prefilledResponse(for: opportunity, organization: organization, form: item.form)
            } else {
                response = .object([:])
            }
            return ApplicationForm(
                applicationFormId: "\(identifier)-form-\(item.form.formId)",
                formId: item.form.formId,
                form: item.form,
                applicationResponse: response,
                isRequired: item.isRequired,
                isIncludedInSubmission: item.isRequired,
                applicationId: identifier,
                applicationName: name
            )
        }
        applicationsByID[identifier] = Application(
            applicationId: identifier,
            applicationName: name,
            applicationStatus: "in_progress",
            competition: competition,
            organization: organization,
            applicationForms: applicationForms
        )
        return identifier
    }

    func application(id: String) throws -> Application {
        guard let application = applicationsByID[id] else { throw GrantsError.notFound }
        return application
    }

    func saveForm(applicationId: String, formId: String, response: JSONValue) throws -> FormSaveResult {
        guard let application = applicationsByID[applicationId],
              let existing = application.applicationForms.first(where: { $0.formId == formId })
        else { throw GrantsError.notFound }
        guard application.applicationStatus != "submitted" else {
            throw GrantsError.server(status: 422, message: "A submitted application cannot be changed.")
        }
        let warnings = RequiredFieldValidator.validate(schema: existing.form.formJsonSchema, response: response)
        let includeResponse: Bool
        if case let .object(values) = response, !values.isEmpty {
            includeResponse = true
        } else {
            includeResponse = false
        }
        let updatedForm = ApplicationForm(
            applicationFormId: existing.applicationFormId,
            formId: existing.formId,
            form: existing.form,
            applicationResponse: response,
            applicationFormStatus: warnings.isEmpty ? "complete" : "in_progress",
            isRequired: existing.isRequired,
            isIncludedInSubmission: existing.isRequired || includeResponse,
            applicationId: existing.applicationId,
            applicationName: existing.applicationName
        )
        let updatedForms = application.applicationForms.map { $0.formId == formId ? updatedForm : $0 }
        let warningsValue = Self.warningObject(existingFormID: updatedForm.applicationFormId, warnings: warnings, previous: application.formValidationWarnings)
        applicationsByID[applicationId] = Self.copy(
            application,
            forms: updatedForms,
            warnings: warningsValue
        )
        return FormSaveResult(warnings: warnings, form: updatedForm)
    }

    func submit(applicationId: String) throws -> SubmissionResult {
        guard let application = applicationsByID[applicationId] else { throw GrantsError.notFound }
        guard application.applicationStatus == "in_progress" else {
            throw GrantsError.server(
                status: 403,
                message: "Cannot submit application. It is currently in status: \(application.applicationStatus)"
            )
        }
        guard !application.applicationForms.contains(where: {
            ($0.isRequired || $0.isIncludedInSubmission == true) && $0.applicationFormStatus != "complete"
        }) else {
            throw GrantsError.server(status: 422, message: "Complete all required forms before submitting.")
        }
        let requiresOrganization = application.competition.openToApplicants.contains("organization")
            && !application.competition.openToApplicants.contains("individual")
        guard !requiresOrganization || application.organization != nil else {
            throw GrantsError.server(status: 422, message: "Application requires organization in order to submit")
        }
        applicationsByID[applicationId] = Self.copy(application, status: "submitted")
        nextTrackingNumber += 1
        return SubmissionResult(applicationId: applicationId, trackingNumber: "GRANT\(nextTrackingNumber)")
    }

    func savedOpportunityIds() -> Set<String> { savedIds }

    func setSaved(_ saved: Bool, opportunityId: String) {
        if saved { savedIds.insert(opportunityId) } else { savedIds.remove(opportunityId) }
    }

    private func summary(for application: Application) -> ApplicationSummary? {
        guard let detail = details.first(where: { $0.competitions.contains(where: { $0.competitionId == application.competition.competitionId }) }),
              let competition = detail.competitions.first(where: { $0.competitionId == application.competition.competitionId })
        else { return nil }
        return ApplicationSummary(
            applicationId: application.applicationId,
            applicationName: application.applicationName,
            applicationStatus: application.applicationStatus,
            organization: application.organization,
            competition: ApplicationCompetition(
                competitionId: competition.competitionId,
                competitionTitle: competition.competitionTitle,
                openingDate: competition.openingDate,
                closingDate: competition.closingDate,
                isOpen: competition.isOpen,
                opportunity: ApplicationOpportunity(
                    opportunityId: detail.opportunityId,
                    opportunityTitle: detail.opportunityTitle,
                    agencyName: detail.agencyName
                )
            )
        )
    }

    private static func seedApplication(
        organization: Organization,
        opportunity: Opportunity,
        competition: Competition
    ) -> Application {
        let overrides = loadSeedResponses()
        let completed: Set<String> = [SampleFormIDs.sf424a, SampleFormIDs.narrative, SampleFormIDs.site]
        let applicationID = "sample-application-0001"
        let applicationName = "Bluefield Rural Recovery Consortium"
        let applicationForms = competition.competitionForms.map { item in
            let form = item.form
            let response: JSONValue
            if form.formId == SampleFormIDs.sf424 {
                let contact = JSONValue.object([
                    "organization_name": .string(organization.samGovEntity?.legalBusinessName ?? ""),
                    "sam_uei": .string(organization.samGovEntity?.uei ?? ""),
                    "contact_person": .object(["first_name": .string("Dana"), "last_name": .string("Reyes")]),
                    "phone_number": .string("(304) 555-0142")
                ])
                response = merge(
                    Self.prefilledResponse(for: opportunity, organization: organization, form: form),
                    contact
                )
            } else if completed.contains(form.formId) {
                let generated = RequiredFieldValidator.minimalInstance(schema: form.formJsonSchema)
                response = merge(generated, overrides[form.formId] ?? .object([:]))
            } else {
                response = .object([:])
            }
            let status = completed.contains(form.formId)
                && RequiredFieldValidator.validate(schema: form.formJsonSchema, response: response).isEmpty
                ? "complete"
                : "in_progress"
            return ApplicationForm(
                applicationFormId: "\(applicationID)-form-\(form.formId)",
                formId: form.formId,
                form: form,
                applicationResponse: response,
                applicationFormStatus: status,
                isRequired: item.isRequired,
                isIncludedInSubmission: item.isRequired,
                applicationId: applicationID,
                applicationName: applicationName
            )
        }
        return Application(
            applicationId: applicationID,
            applicationName: applicationName,
            applicationStatus: "in_progress",
            competition: competition,
            organization: organization,
            applicationForms: applicationForms
        )
    }

    private static func prefilledResponse(
        for opportunity: Opportunity,
        organization: Organization?,
        form: FormDefinition
    ) -> JSONValue {
        var fields: [String: JSONValue] = [:]
        let properties: Set<String>
        if case let .object(schema) = form.formJsonSchema,
           case let .object(values) = schema["properties"] {
            properties = Set(values.keys)
        } else {
            properties = []
        }
        let assistance = opportunity.opportunityAssistanceListings.first
        let prefilled: [String: JSONValue] = [
            "funding_opportunity_number": .string(opportunity.opportunityNumber ?? ""),
            "funding_opportunity_title": .string(opportunity.opportunityTitle ?? ""),
            "agency_name": .string(opportunity.agencyName ?? ""),
            "assistance_listing_number": .string(assistance?.assistanceListingNumber ?? ""),
            "assistance_listing_program_title": .string(assistance?.programTitle ?? ""),
            "organization_name": .string(organization?.samGovEntity?.legalBusinessName ?? ""),
            "sam_uei": .string(organization?.samGovEntity?.uei ?? "")
        ]
        for (key, value) in prefilled where properties.contains(key) { fields[key] = value }
        return .object(fields)
    }

    private static func loadSeedResponses() -> [String: JSONValue] {
        guard let url = Bundle.module.url(forResource: "sample_application", withExtension: "json", subdirectory: "Data"),
              let data = try? Data(contentsOf: url),
              case let .object(object) = try? JSONDecoder().decode(JSONValue.self, from: data),
              case let .object(forms)? = object["forms"]
        else {
            fatalError("SGSampleData could not load Resources/Data/sample_application.json")
        }
        return forms
    }

    private static func warningObject(
        existingFormID: String,
        warnings: [ValidationWarning],
        previous: JSONValue
    ) -> JSONValue {
        var values: [String: JSONValue]
        if case let .object(object) = previous { values = object } else { values = [:] }
        if let data = try? JSONEncoder.sg.encode(warnings),
           let encoded = try? JSONDecoder().decode(JSONValue.self, from: data) {
            values[existingFormID] = encoded
        }
        return .object(values)
    }

    private static func copy(
        _ application: Application,
        forms: [ApplicationForm]? = nil,
        warnings: JSONValue? = nil,
        status: String? = nil
    ) -> Application {
        Application(
            applicationId: application.applicationId,
            applicationName: application.applicationName,
            applicationStatus: status ?? application.applicationStatus,
            competition: application.competition,
            organization: application.organization,
            applicationForms: forms ?? application.applicationForms,
            formValidationWarnings: warnings ?? application.formValidationWarnings,
            intendsToAddOrganization: application.intendsToAddOrganization
        )
    }

    private static func merge(_ base: JSONValue, _ override: JSONValue) -> JSONValue {
        guard case var .object(values) = base, case let .object(overrides) = override else { return override }
        values.merge(overrides) { _, replacement in replacement }
        return .object(values)
    }
}

private enum SampleFormIDs {
    static let sf424 = "1623b310-85be-496a-b84b-34bdee22a68a"
    static let sf424a = "08e6603f-d197-4a60-98cd-d49acb1fc1fd"
    static let narrative = "32165da2-354d-42c0-a986-cf4f2f350039"
    static let site = "6ebd786f-cccf-4ee1-a100-61436975025b"
}
