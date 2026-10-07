import Foundation

public struct RoadmapContent: Codable, Equatable, Sendable {
    public let sections: [RoadmapSection]

    public init(sections: [RoadmapSection]) {
        self.sections = sections
    }

    public static func loadBundled() throws -> RoadmapContent {
        guard let url = Bundle.module.url(forResource: "roadmap", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(RoadmapContent.self, from: Data(contentsOf: url))
    }
}

public struct RoadmapSection: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let items: [RoadmapItem]

    public init(id: String, title: String, items: [RoadmapItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct RoadmapItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let status: RoadmapItemStatus
    public let title: String
    public let summary: String
    public let baseVotes: Int?

    public init(
        id: String,
        status: RoadmapItemStatus,
        title: String,
        summary: String,
        baseVotes: Int?
    ) {
        self.id = id
        self.status = status
        self.title = title
        self.summary = summary
        self.baseVotes = baseVotes
    }
}

public enum RoadmapItemStatus: String, Codable, Equatable, Sendable {
    case inProgress = "in_progress"
    case planned
    case released

    var localizationKey: String {
        switch self {
        case .inProgress: "roadmap.status.in_progress"
        case .planned: "roadmap.status.planned"
        case .released: "roadmap.status.released"
        }
    }
}
