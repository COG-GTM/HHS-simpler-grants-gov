import Foundation
import Observation
import SGModels

public struct SavedOpportunity: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

@Observable
@MainActor
public final class ProfileModel {
    public private(set) var organization: Organization?
    public private(set) var savedOpportunityIds: Set<String> = []
    public private(set) var savedOpportunities: [SavedOpportunity] = []
    public private(set) var isLoading = false
    public private(set) var isLoaded = false
    public private(set) var loadError: GrantsError?
    public private(set) var loadedUserId: String?

    private var loadingUserId: String?
    private var activeLoadID: UUID?

    public init() {}

    public func reset() {
        activeLoadID = nil
        loadingUserId = nil
        organization = nil
        savedOpportunityIds = []
        savedOpportunities = []
        isLoading = false
        isLoaded = false
        loadError = nil
        loadedUserId = nil
    }

    public func load(from dataSource: any GrantsDataSource, userId: String) async {
        guard !(isLoading && loadingUserId == userId) else { return }
        if loadedUserId != userId || loadingUserId != nil {
            reset()
        }

        let loadID = UUID()
        activeLoadID = loadID
        loadingUserId = userId
        isLoading = true
        isLoaded = false
        loadedUserId = nil
        loadError = nil
        defer {
            if activeLoadID == loadID {
                isLoading = false
                loadingUserId = nil
                activeLoadID = nil
            }
        }

        do {
            let organizations = try await dataSource.organizations()
            guard activeLoadID == loadID else { return }

            let opportunityIds = try await dataSource.savedOpportunityIds()
            guard activeLoadID == loadID else { return }

            let opportunities = await withTaskGroup(of: SavedOpportunity?.self) { group in
                for id in opportunityIds.sorted() {
                    group.addTask {
                        guard
                            let detail = try? await dataSource.opportunity(id: id),
                            let title = detail.opportunityTitle
                        else {
                            return nil
                        }
                        return SavedOpportunity(id: id, title: title)
                    }
                }
                var opportunities: [SavedOpportunity] = []
                for await opportunity in group {
                    if let opportunity {
                        opportunities.append(opportunity)
                    }
                }
                return opportunities.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }

            guard activeLoadID == loadID else { return }
            organization = organizations.first
            savedOpportunityIds = opportunityIds
            savedOpportunities = opportunities
            loadedUserId = userId
            isLoaded = true
        } catch {
            guard activeLoadID == loadID else { return }
            organization = nil
            savedOpportunityIds = []
            savedOpportunities = []
            loadError = Self.grantsError(from: error)
        }
    }

    private static func grantsError(from error: Error) -> GrantsError {
        (error as? GrantsError) ?? .server(status: 500, message: error.localizedDescription)
    }
}
