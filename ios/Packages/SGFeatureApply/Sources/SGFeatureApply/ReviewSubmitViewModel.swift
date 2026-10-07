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

private struct ParsedReviewWarning {
    let field: String
    let message: String
}

private struct ReviewWarningKey: Hashable {
    let formId: String
    let field: String
    let message: String

    var id: String {
        "\(formId)/\(field)/\(message)"
    }
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
            let cached = await ApplyWarningsCache.shared.all(applicationId: applicationId)
            warnings = Self.parseWarnings(
                application.formValidationWarnings,
                forms: application.applicationForms,
                cachedWarnings: cached
            )
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
        forms: [ApplicationForm],
        cachedWarnings: [String: [ValidationWarning]]
    ) -> [ReviewWarning] {
        let warningsByForm: [String: JSONValue]
        if case let .object(warningValues) = value {
            warningsByForm = warningValues
        } else {
            warningsByForm = [:]
        }
        var result: [ReviewWarning] = []
        var seen = Set<ReviewWarningKey>()
        for form in forms {
            let formName = ApplyFormStateLogic.displayName(
                formName: form.form.formName,
                shortName: form.form.shortFormName,
                formId: form.formId
            )
            let formWarnings: [ParsedReviewWarning]
            if let cachedFormWarnings = cachedWarnings[form.formId] {
                formWarnings = cachedFormWarnings.map {
                    ParsedReviewWarning(field: $0.field, message: $0.message)
                }
            } else {
                var persistedWarnings: [ParsedReviewWarning] = []
                for key in [form.applicationFormId, form.formId] {
                    guard case let .array(warnings)? = warningsByForm[key] else { continue }
                    for warning in warnings {
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
                        persistedWarnings.append(
                            ParsedReviewWarning(field: field, message: message)
                        )
                    }
                }
                formWarnings = persistedWarnings
            }
            for warning in formWarnings {
                let key = ReviewWarningKey(
                    formId: form.formId,
                    field: warning.field,
                    message: warning.message
                )
                guard seen.insert(key).inserted else { continue }
                result.append(
                    ReviewWarning(
                        id: key.id,
                        formName: formName,
                        message: warning.message
                    )
                )
            }
        }
        return result
    }
}
