import Foundation
import SGCore
import SGForms
import SGModels

struct LoadedApplication {
    let application: Application
    let opportunityNumber: String?
    let opportunityTitle: String
    let agencyName: String?
    let organizationName: String
    let requiredRows: [ApplyFormRow]
    let optionalRows: [ApplyFormRow]
}

enum ApplicationLoader {
    static func load(
        applicationId: String,
        summary: ApplicationSummary? = nil,
        dataSource: any GrantsDataSource,
        draftStore: any DraftStore,
        progressStore: any FormProgressStore
    ) async throws -> LoadedApplication {
        let application = try await dataSource.application(id: applicationId)
        let matchingSummary: ApplicationSummary?
        if let summary, summary.applicationId == applicationId {
            matchingSummary = summary
        } else if application.competition.opportunityId == nil {
            let summaries = try? await dataSource.applications()
            matchingSummary = summaries?.first { $0.applicationId == applicationId }
        } else {
            matchingSummary = nil
        }
        let summaryOpportunity = matchingSummary?.competition.opportunity
        let opportunityId = application.competition.opportunityId
            ?? summaryOpportunity?.opportunityId
        let opportunity: OpportunityDetail?
        if let opportunityId {
            opportunity = try? await dataSource.opportunity(id: opportunityId)
        } else {
            opportunity = nil
        }

        var required: [ApplyFormRow] = []
        var optional: [ApplyFormRow] = []
        for form in application.applicationForms {
            let formId = form.formId
            let model = try? FormModel(definition: form.form)
            let sectionIds = model?.sections.map(\.id) ?? []
            let draft = try? await draftStore.loadDraft(
                applicationId: applicationId,
                formId: formId
            )
            let completedSections = await progressStore.completedSections(
                applicationId: applicationId,
                formId: formId
            )
            let isComplete = await progressStore.isFormComplete(
                applicationId: applicationId,
                formId: formId
            )
            let row = ApplyFormRow(
                id: formId,
                applicationFormId: form.applicationFormId,
                displayName: ApplyFormStateLogic.displayName(
                    formName: form.form.formName,
                    shortName: form.form.shortFormName,
                    formId: formId
                ),
                shortName: form.form.shortFormName ?? formId,
                isRequired: form.isRequired,
                state: ApplyFormStateLogic.state(
                    serverStatus: form.applicationFormStatus,
                    response: form.applicationResponse,
                    hasDraft: draft != nil,
                    completedSectionIds: completedSections,
                    sectionIds: sectionIds,
                    locallyComplete: isComplete
                )
            )
            if form.isRequired {
                required.append(row)
            } else {
                optional.append(row)
            }
        }

        let title = [
            opportunity?.opportunityTitle,
            summaryOpportunity?.opportunityTitle,
            application.competition.competitionTitle,
            matchingSummary?.competition.competitionTitle,
            application.applicationName
        ]
        .compactMap { $0 }
        .first { !$0.isEmpty } ?? ""
        let number = opportunity?.opportunityNumber.flatMap { $0.isEmpty ? nil : $0 }
        let agency = opportunity?.agencyName
            ?? opportunity?.topLevelAgencyName
            ?? summaryOpportunity?.agencyName
        return LoadedApplication(
            application: application,
            opportunityNumber: number,
            opportunityTitle: title,
            agencyName: agency,
            organizationName: application.organization?.samGovEntity?.legalBusinessName
                ?? matchingSummary?.organization?.samGovEntity?.legalBusinessName
                ?? "",
            requiredRows: required,
            optionalRows: optional
        )
    }
}
