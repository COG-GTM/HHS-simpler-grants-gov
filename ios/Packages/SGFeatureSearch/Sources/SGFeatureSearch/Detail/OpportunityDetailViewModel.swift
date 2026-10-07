import Foundation
import Observation
import SGModels

@Observable
@MainActor
public final class OpportunityDetailViewModel {
    public enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(GrantsError)
    }

    public private(set) var detail: OpportunityDetail?
    public private(set) var isSaved = false
    public private(set) var isSavingBookmark = false
    public private(set) var saveError: GrantsError?
    public private(set) var actionError: GrantsError?
    public private(set) var phase: Phase = .idle
    public private(set) var isStartingApplication = false
    public let opportunityId: String
    public private(set) var now: Date

    private let dataSource: any GrantsDataSource
    private let clock: @Sendable () -> Date
    private var generation = 0

    public init(opportunityId: String, dataSource: any GrantsDataSource, now: Date? = nil) {
        self.opportunityId = opportunityId
        self.dataSource = dataSource
        if let now {
            clock = { now }
        } else {
            clock = { Date() }
        }
        self.now = clock()
    }

    public func load() async {
        now = clock()
        generation += 1
        let requestGeneration = generation
        phase = .loading
        do {
            let detail = try await dataSource.opportunity(id: opportunityId)
            guard requestGeneration == generation else { return }
            self.detail = detail
            phase = .loaded
        } catch let error as GrantsError {
            guard requestGeneration == generation else { return }
            phase = .failed(error)
        } catch {
            guard requestGeneration == generation else { return }
            phase = .failed(.server(status: 500, message: error.localizedDescription))
        }
        if let saved = try? await dataSource.savedOpportunityIds(), requestGeneration == generation {
            isSaved = saved.contains(opportunityId)
        }
    }

    public func toggleSaved() async {
        guard !isSavingBookmark else { return }
        let previous = isSaved
        isSavingBookmark = true
        isSaved.toggle()
        saveError = nil
        defer { isSavingBookmark = false }
        do {
            try await dataSource.setSaved(isSaved, opportunityId: opportunityId)
        } catch let error as GrantsError {
            isSaved = previous
            saveError = error
        } catch {
            isSaved = previous
            saveError = .server(status: 500, message: error.localizedDescription)
        }
    }

    public func startApplication(_ competition: Competition) async -> String? {
        guard let detail else { return nil }
        isStartingApplication = true
        actionError = nil
        defer { isStartingApplication = false }
        do {
            let organizationId = try await dataSource.organizations().first?.organizationId
            return try await dataSource.startApplication(
                competitionId: competition.competitionId,
                name: detail.opportunityTitle ?? detail.opportunityNumber ?? "",
                organizationId: organizationId
            )
        } catch let error as GrantsError {
            actionError = error
        } catch {
            actionError = .server(status: 500, message: error.localizedDescription)
        }
        return nil
    }
}
