import Foundation
import Observation

@Observable
@MainActor
public final class RoadmapVoteStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "sg.roadmap.votes"
    private var votedIDs: Set<String>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        votedIDs = Set(defaults.stringArray(forKey: "sg.roadmap.votes") ?? [])
    }

    public func hasVoted(_ id: String) -> Bool {
        votedIDs.contains(id)
    }

    public func toggle(_ id: String) {
        if votedIDs.contains(id) {
            votedIDs.remove(id)
        } else {
            votedIDs.insert(id)
        }
        defaults.set(votedIDs.sorted(), forKey: key)
    }

    public func count(for item: RoadmapItem) -> Int? {
        guard item.status != .released else { return nil }
        return (item.baseVotes ?? 0) + (hasVoted(item.id) ? 1 : 0)
    }
}
