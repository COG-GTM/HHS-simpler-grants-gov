import Foundation

public struct SearchRequest: Codable, Sendable, Hashable {
    public let query: String?
    public let queryOperator: String
    public let filters: SearchFilters
    public let pagination: SearchPagination

    public init(
        query: String? = nil,
        queryOperator: String = "AND",
        filters: SearchFilters = SearchFilters(),
        pagination: SearchPagination = SearchPagination()
    ) {
        self.query = query
        self.queryOperator = queryOperator
        self.filters = filters
        self.pagination = pagination
    }
}

public struct SearchFilters: Codable, Sendable, Hashable {
    public var opportunityStatus: [String]
    public var applicantType: [String]
    public var fundingCategory: [String]
    public var fundingInstrument: [String]
    public var agency: [String]

    public init(
        opportunityStatus: [String] = [],
        applicantType: [String] = [],
        fundingCategory: [String] = [],
        fundingInstrument: [String] = [],
        agency: [String] = []
    ) {
        self.opportunityStatus = opportunityStatus
        self.applicantType = applicantType
        self.fundingCategory = fundingCategory
        self.fundingInstrument = fundingInstrument
        self.agency = agency
    }

    private struct OneOf: Codable, Hashable {
        let oneOf: [String]
    }

    private enum CodingKeys: String, CodingKey {
        case opportunityStatus
        case applicantType
        case fundingCategory
        case fundingInstrument
        case agency
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opportunityStatus = try container.decodeIfPresent(OneOf.self, forKey: .opportunityStatus)?.oneOf ?? []
        applicantType = try container.decodeIfPresent(OneOf.self, forKey: .applicantType)?.oneOf ?? []
        fundingCategory = try container.decodeIfPresent(OneOf.self, forKey: .fundingCategory)?.oneOf ?? []
        fundingInstrument = try container.decodeIfPresent(OneOf.self, forKey: .fundingInstrument)?.oneOf ?? []
        agency = try container.decodeIfPresent(OneOf.self, forKey: .agency)?.oneOf ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !opportunityStatus.isEmpty {
            try container.encode(OneOf(oneOf: opportunityStatus), forKey: .opportunityStatus)
        }
        if !applicantType.isEmpty {
            try container.encode(OneOf(oneOf: applicantType), forKey: .applicantType)
        }
        if !fundingCategory.isEmpty {
            try container.encode(OneOf(oneOf: fundingCategory), forKey: .fundingCategory)
        }
        if !fundingInstrument.isEmpty {
            try container.encode(OneOf(oneOf: fundingInstrument), forKey: .fundingInstrument)
        }
        if !agency.isEmpty {
            try container.encode(OneOf(oneOf: agency), forKey: .agency)
        }
    }
}

public struct SearchPagination: Codable, Sendable, Hashable {
    public let pageOffset: Int
    public let pageSize: Int
    public let sortOrder: [SortOrder]

    public init(pageOffset: Int = 1, pageSize: Int = 10, sortOrder: [SortOrder] = []) {
        self.pageOffset = pageOffset
        self.pageSize = pageSize
        self.sortOrder = sortOrder
    }
}

public struct SortOrder: Codable, Sendable, Hashable {
    public let orderBy: String
    public let sortDirection: String

    public init(orderBy: String, sortDirection: String) {
        self.orderBy = orderBy
        self.sortDirection = sortDirection
    }
}

public struct PaginationInfo: Codable, Sendable, Hashable {
    public let pageOffset: Int?
    public let pageSize: Int?
    public let sortOrder: [SortOrder]?
    public let totalPages: Int?
    public let totalRecords: Int?

    public init(
        pageOffset: Int? = nil,
        pageSize: Int? = nil,
        sortOrder: [SortOrder]? = nil,
        totalPages: Int? = nil,
        totalRecords: Int? = nil
    ) {
        self.pageOffset = pageOffset
        self.pageSize = pageSize
        self.sortOrder = sortOrder
        self.totalPages = totalPages
        self.totalRecords = totalRecords
    }
}

public struct SearchResponse: Codable, Sendable, Hashable {
    public let data: [Opportunity]
    public let paginationInfo: PaginationInfo
    public let facetCounts: [String: [String: Int]]

    public init(
        data: [Opportunity],
        paginationInfo: PaginationInfo,
        facetCounts: [String: [String: Int]]
    ) {
        self.data = data
        self.paginationInfo = paginationInfo
        self.facetCounts = facetCounts
    }
}
