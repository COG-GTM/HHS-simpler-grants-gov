import Foundation
import Observation
import SGCore
import SGModels

public enum ApplyLoadPhase: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

@MainActor
@Observable
public final class WorkspaceViewModel {
    public let applicationId: String?
    public private(set) var loadedApplicationId: String?
    public private(set) var phase: ApplyLoadPhase = .loading
    public private(set) var opportunityNumber: String?
    public private(set) var opportunityTitle = ""
    public private(set) var agencyName: String?
    public private(set) var organizationName = ""
    public private(set) var requiredRows: [ApplyFormRow] = []
    public private(set) var optionalRows: [ApplyFormRow] = []
    public private(set) var allApplications: [ApplicationSummary] = []
    public private(set) var dueDate: Date?
    public private(set) var daysRemaining: Int?

    private let dataSource: any GrantsDataSource
    private let draftStore: any DraftStore
    private let progressStore: any FormProgressStore
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone
    private var selectedSummary: ApplicationSummary?

    public init(
        applicationId: String?,
        dataSource: any GrantsDataSource,
        draftStore: any DraftStore,
        progressStore: any FormProgressStore,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .current
    ) {
        self.applicationId = applicationId
        self.dataSource = dataSource
        self.draftStore = draftStore
        self.progressStore = progressStore
        self.now = now
        self.timeZone = timeZone
    }

    public convenience init(
        applicationId: String?,
        dataSource: any GrantsDataSource,
        progressStore: any FormProgressStore,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .current
    ) {
        self.init(
            applicationId: applicationId,
            dataSource: dataSource,
            draftStore: InMemoryApplyDraftStore(),
            progressStore: progressStore,
            now: now,
            timeZone: timeZone
        )
    }

    public var completedRequiredCount: Int {
        requiredRows.filter { $0.state == .complete }.count
    }

    public var requiredCount: Int { requiredRows.count }

    public var progressFraction: Double {
        guard requiredCount > 0 else { return 0 }
        return Double(completedRequiredCount) / Double(requiredCount)
    }

    public var isDueSoon: Bool {
        guard let daysRemaining else { return false }
        return daysRemaining <= 90
    }

    public var canReview: Bool {
        requiredCount > 0 && completedRequiredCount == requiredCount
    }

    public func load() async {
        if phase != .loaded { phase = .loading }
        do {
            let id: String
            if let applicationId {
                id = applicationId
            } else {
                allApplications = try await dataSource.applications()
                guard !allApplications.isEmpty else {
                    clearLoadedApplication()
                    phase = .empty
                    return
                }
                selectedSummary = allApplications.first {
                    $0.applicationStatus.caseInsensitiveCompare("in_progress") == .orderedSame
                } ?? allApplications.first
                guard let selectedSummary else {
                    clearLoadedApplication()
                    phase = .empty
                    return
                }
                id = selectedSummary.applicationId
            }
            let loaded = try await ApplicationLoader.load(
                applicationId: id,
                summary: selectedSummary,
                dataSource: dataSource,
                draftStore: draftStore,
                progressStore: progressStore
            )
            loadedApplicationId = id
            opportunityNumber = loaded.opportunityNumber
            opportunityTitle = loaded.opportunityTitle
            agencyName = loaded.agencyName
            organizationName = loaded.organizationName
            requiredRows = loaded.requiredRows
            optionalRows = loaded.optionalRows
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            dueDate = Self.parseDate(loaded.application.competition.closingDate, calendar: calendar)
            daysRemaining = dueDate.map {
                calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: now()),
                    to: calendar.startOfDay(for: $0)
                ).day ?? 0
            }
            phase = .loaded
        } catch {
            phase = .failed("apply.error.load".localized(bundle: .module))
        }
    }

    private func clearLoadedApplication() {
        opportunityNumber = nil
        opportunityTitle = ""
        agencyName = nil
        organizationName = ""
        requiredRows = []
        optionalRows = []
        dueDate = nil
        daysRemaining = nil
        loadedApplicationId = nil
    }

    private static func parseDate(_ value: String?, calendar: Calendar) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
