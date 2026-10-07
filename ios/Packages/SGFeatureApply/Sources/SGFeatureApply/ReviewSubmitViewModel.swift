import Foundation
import Observation
import SGCore
import SGModels

public struct ReviewWarning: Identifiable, Hashable, Sendable {
    public let id: String
    public let formName: String
    public let message: String

    public init(id: String, formName: String, message: String) {
        self.id = id
        self.formName = formName
        self.message = message
    }
}

public enum SubmitStep: Sendable, Equatable {
    case ignored
    case confirmationRequired
    case denied
    case submitted(SubmissionResult?)
}

@MainActor
@Observable
public final class ReviewSubmitViewModel {
    public let applicationId: String
    public private(set) var phase: ApplyLoadPhase = .loading
    public private(set) var opportunityTitle = ""
    public private(set) var agencyName: String?
    public private(set) var organizationName = ""
    public private(set) var requiredRows: [ApplyFormRow] = []
    public private(set) var optionalRows: [ApplyFormRow] = []
    public private(set) var warnings: [ReviewWarning] = []
    public var certified = false
    public private(set) var isSubmitting = false
    public private(set) var bannerMessage: String?
    public var showConfirmation = false
    public private(set) var submissionResult: SubmissionResult?

    private let dataSource: any GrantsDataSource
    private let draftStore: any DraftStore
    private let progressStore: any FormProgressStore
    private let authorizer: any SubmissionAuthorizing

    public init(
        applicationId: String,
        dataSource: any GrantsDataSource,
        draftStore: any DraftStore,
        progressStore: any FormProgressStore,
        authorizer: any SubmissionAuthorizing
    ) {
        self.applicationId = applicationId
        self.dataSource = dataSource
        self.draftStore = draftStore
        self.progressStore = progressStore
        self.authorizer = authorizer
    }

    public convenience init(
        applicationId: String,
        dataSource: any GrantsDataSource,
        progressStore: any FormProgressStore,
        authorizer: any SubmissionAuthorizing
    ) {
        self.init(
            applicationId: applicationId,
            dataSource: dataSource,
            draftStore: InMemoryApplyDraftStore(),
            progressStore: progressStore,
            authorizer: authorizer
        )
    }

    public var incompleteRequiredCount: Int {
        requiredRows.filter { $0.state != .complete }.count
    }

    public var canSubmit: Bool {
        phase == .loaded && incompleteRequiredCount == 0 && certified && !isSubmitting
    }

    public func load() async {
        if phase != .loaded { phase = .loading }
        do {
            let application = try await dataSource.application(id: applicationId)
            let loaded = try await ApplicationLoader.load(
                applicationId: applicationId,
                dataSource: dataSource,
                draftStore: draftStore,
                progressStore: progressStore
            )
            opportunityTitle = loaded.opportunityTitle
            agencyName = loaded.agencyName
            organizationName = loaded.organizationName
            requiredRows = loaded.requiredRows
            optionalRows = loaded.optionalRows
            warnings = Self.parseWarnings(
                application.formValidationWarnings,
                forms: application.applicationForms
            )
            let cached = await ApplyWarningsCache.shared.all(applicationId: applicationId)
            for form in application.applicationForms {
                for warning in cached[form.formId] ?? [] {
                    warnings.append(
                        ReviewWarning(
                            id: "\(form.formId)/\(warning.field)/\(warning.message)",
                            formName: ApplyFormStateLogic.displayName(
                                formName: form.form.formName,
                                shortName: form.form.shortFormName,
                                formId: form.formId
                            ),
                            message: warning.message
                        )
                    )
                }
            }
            phase = .loaded
        } catch {
            phase = .failed("apply.error.load".localized(bundle: .module))
        }
    }

    public func requestSubmit() async -> SubmitStep {
        guard canSubmit else { return .ignored }
        switch await authorizer.authorize(reason: "apply.review.authorization_reason".localized(bundle: .module)) {
        case .authorized:
            return .submitted(await performSubmit())
        case .unavailable:
            showConfirmation = true
            return .confirmationRequired
        case .denied:
            return .denied
        }
    }

    public func performSubmit() async -> SubmissionResult? {
        guard canSubmit else { return nil }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result = try await dataSource.submit(applicationId: applicationId)
            submissionResult = result
            bannerMessage = nil
            showConfirmation = false
            return result
        } catch {
            bannerMessage = "apply.review.submit_failed".localized(bundle: .module)
            return nil
        }
    }

    private static func parseWarnings(
        _ value: JSONValue,
        forms: [ApplicationForm]
    ) -> [ReviewWarning] {
        guard case let .object(warningsByForm) = value else { return [] }
        var result: [ReviewWarning] = []
        for form in forms {
            for key in [form.applicationFormId, form.formId] {
                guard case let .array(warnings)? = warningsByForm[key] else { continue }
                for (index, warning) in warnings.enumerated() {
                    guard case let .object(fields) = warning,
                          case let .string(message)? = fields["message"] else {
                        continue
                    }
                    let field: String
                    if case let .string(value)? = fields["field"] {
                        field = value
                    } else {
                        field = ""
                    }
                    result.append(
                        ReviewWarning(
                            id: "\(key)/\(index)/\(field)",
                            formName: ApplyFormStateLogic.displayName(
                                formName: form.form.formName,
                                shortName: form.form.shortFormName,
                                formId: form.formId
                            ),
                            message: message
                        )
                    )
                }
            }
        }
        return result
    }
}
