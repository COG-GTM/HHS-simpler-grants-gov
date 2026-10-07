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

    public init() {}

    public func load(from dataSource: any GrantsDataSource) async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil

        do {
            organization = try await dataSource.organizations().first
        } catch {
            loadError = Self.grantsError(from: error)
        }

        do {
            savedOpportunityIds = try await dataSource.savedOpportunityIds()
            savedOpportunities = await withTaskGroup(of: SavedOpportunity?.self) { group in
                for id in savedOpportunityIds.sorted() {
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
        } catch {
            loadError = loadError ?? Self.grantsError(from: error)
            savedOpportunityIds = []
            savedOpportunities = []
        }

        isLoaded = true
        isLoading = false
    }

    private static func grantsError(from error: Error) -> GrantsError {
        (error as? GrantsError) ?? .server(status: 500, message: error.localizedDescription)
    }
}
