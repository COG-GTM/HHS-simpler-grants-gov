import Foundation
import Observation

public struct RecentSearch: Codable, Hashable, Sendable {
    public let query: String
    public var resultCount: Int?

    public init(query: String, resultCount: Int? = nil) {
        self.query = query
        self.resultCount = resultCount
    }
}

@Observable
@MainActor
public final class RecentSearchStore {
    public static let shared = RecentSearchStore()

    public private(set) var items: [RecentSearch]
    private let defaults: UserDefaults
    private let key: String
    private let limit: Int

    public init(
        defaults: UserDefaults = .standard,
        key: String = "sg.search.recents",
        limit: Int = 8
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = max(0, limit)
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RecentSearch].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    public func record(_ query: String) {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let previous = items.first { $0.query.caseInsensitiveCompare(cleaned) == .orderedSame }
        items.removeAll { $0.query.caseInsensitiveCompare(cleaned) == .orderedSame }
        items.insert(RecentSearch(query: cleaned, resultCount: previous?.resultCount), at: 0)
        items = Array(items.prefix(limit))
        persist()
    }

    public func updateCount(_ count: Int, for query: String) {
        guard let index = items.firstIndex(where: { $0.query.caseInsensitiveCompare(query) == .orderedSame }) else {
            return
        }
        items[index].resultCount = count
        persist()
    }

    public func clear() {
        items = []
        defaults.removeObject(forKey: key)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
}
