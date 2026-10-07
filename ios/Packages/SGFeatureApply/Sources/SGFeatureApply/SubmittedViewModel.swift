import Foundation
import Observation
import SGModels

@MainActor
@Observable
public final class SubmittedViewModel {
    public let applicationId: String
    public let trackingNumber: String?
    public let submittedAt: Date
    public private(set) var closingDate: String?

    private let dataSource: any GrantsDataSource

    public init(
        applicationId: String,
        trackingNumber: String?,
        dataSource: any GrantsDataSource,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.applicationId = applicationId
        self.trackingNumber = trackingNumber
        submittedAt = now()
        self.dataSource = dataSource
    }

    public func load() async {
        guard let application = try? await dataSource.application(id: applicationId) else { return }
        closingDate = Self.formatClosingDate(application.competition.closingDate)
    }

    private static func formatClosingDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let source = DateFormatter()
        source.locale = Locale(identifier: "en_US_POSIX")
        source.calendar = Calendar(identifier: .gregorian)
        source.timeZone = .current
        source.dateFormat = "yyyy-MM-dd"
        guard let date = source.date(from: value) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
