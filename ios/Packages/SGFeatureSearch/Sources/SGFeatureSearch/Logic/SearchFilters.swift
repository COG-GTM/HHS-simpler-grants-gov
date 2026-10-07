import Foundation
import SGModels

public struct FilterOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let titleKey: String
    public let values: [String]
    public let group: FilterGroup

    public init(id: String, titleKey: String, values: [String], group: FilterGroup) {
        self.id = id
        self.titleKey = titleKey
        self.values = values
        self.group = group
    }
}

public enum FilterGroup: String, CaseIterable, Sendable {
    case status
    case applicantType
    case fundingCategory
    case fundingInstrument
    case agency

    public var facetKey: String {
        switch self {
        case .status: return "opportunity_status"
        case .applicantType: return "applicant_type"
        case .fundingCategory: return "funding_category"
        case .fundingInstrument: return "funding_instrument"
        case .agency: return "agency"
        }
    }

    public var filtersKeyPath: WritableKeyPath<SearchFilters, [String]> {
        switch self {
        case .status: return \.opportunityStatus
        case .applicantType: return \.applicantType
        case .fundingCategory: return \.fundingCategory
        case .fundingInstrument: return \.fundingInstrument
        case .agency: return \.agency
        }
    }

    public var titleKey: String {
        switch self {
        case .status: return "search.filter.group.status"
        case .applicantType: return "search.filter.group.eligibility"
        case .fundingCategory: return "search.filter.group.category"
        case .fundingInstrument: return "search.filter.group.funding_instrument"
        case .agency: return "search.filter.group.agency"
        }
    }
}

public enum SearchFilterCatalog {
    public static let allApplicantTypeValues: [String] = [
        "state_governments",
        "county_governments",
        "city_or_township_governments",
        "special_district_governments",
        "independent_school_districts",
        "public_and_state_institutions_of_higher_education",
        "private_institutions_of_higher_education",
        "federally_recognized_native_american_tribal_governments",
        "other_native_american_tribal_organizations",
        "public_and_indian_housing_authorities",
        "nonprofits_non_higher_education_with_501c3",
        "nonprofits_non_higher_education_without_501c3",
        "individuals",
        "for_profit_organizations_other_than_small_businesses",
        "small_businesses",
        "other",
        "unrestricted"
    ]

    public static func options(in group: FilterGroup, agencyCodes: [String] = []) -> [FilterOption] {
        switch group {
        case .status:
            return [
                option("open", group: group, values: ["posted"]),
                option("forecasted", group: group, values: ["forecasted"]),
                option("closed", group: group, values: ["closed"]),
                option("archived", group: group, values: ["archived"])
            ]
        case .applicantType:
            return [
                option("nonprofits", group: group, values: ["nonprofits_non_higher_education_with_501c3", "nonprofits_non_higher_education_without_501c3"]),
                option("local_governments", group: group, values: ["county_governments", "city_or_township_governments", "special_district_governments"]),
                option("state_governments", group: group, values: ["state_governments"]),
                option("tribal_governments", group: group, values: ["federally_recognized_native_american_tribal_governments", "other_native_american_tribal_organizations"]),
                option("universities", group: group, values: ["public_and_state_institutions_of_higher_education", "private_institutions_of_higher_education"]),
                option("individuals", group: group, values: ["individuals"]),
                option("small_businesses", group: group, values: ["small_businesses"])
            ]
        case .fundingCategory:
            return [
                option("health", group: group, values: ["health"]),
                option("education", group: group, values: ["education"]),
                option("environment", group: group, values: ["environment"]),
                option("arts", group: group, values: ["arts"]),
                option("agriculture", group: group, values: ["agriculture"]),
                option("science", group: group, values: ["science_technology_and_other_research_and_development"])
            ]
        case .fundingInstrument:
            return [
                option("grant", group: group, values: ["grant"]),
                option("cooperative_agreement", group: group, values: ["cooperative_agreement"]),
                option("procurement_contract", group: group, values: ["procurement_contract"]),
                option("other", group: group, values: ["other"])
            ]
        case .agency:
            let known = ["HHS", "USDA", "NSF", "EPA", "NEA", "DOJ"]
            return (known + agencyCodes.filter { !known.contains($0) }.sorted())
                .map { code in
                    FilterOption(
                        id: code.lowercased(),
                        titleKey: known.contains(code) ? "search.filter.agency.\(code.lowercased())" : "",
                        values: [code],
                        group: group
                    )
                }
        }
    }

    public static func browseCategories() -> [BrowseCategory] {
        [
            BrowseCategory(id: "health", titleKey: "search.category.health", values: ["health"]),
            BrowseCategory(id: "education", titleKey: "search.category.education", values: ["education"]),
            BrowseCategory(id: "environment", titleKey: "search.category.environment", values: ["environment"]),
            BrowseCategory(id: "community_development", titleKey: "search.category.community_development", values: ["community_development"]),
            BrowseCategory(id: "agriculture", titleKey: "search.category.agriculture", values: ["agriculture"]),
            BrowseCategory(id: "science", titleKey: "search.category.science", values: ["science_technology_and_other_research_and_development"]),
            BrowseCategory(id: "arts_humanities", titleKey: "search.category.arts_humanities", values: ["arts", "humanities"]),
            BrowseCategory(id: "public_safety", titleKey: "search.category.public_safety", values: ["law_justice_and_legal_services", "disaster_prevention_and_relief"])
        ]
    }

    public static func isSelected(_ option: FilterOption, in filters: SearchFilters) -> Bool {
        option.values.allSatisfy(filters[keyPath: option.group.filtersKeyPath].contains)
    }

    public static func toggle(_ option: FilterOption, in filters: inout SearchFilters) {
        let keyPath = option.group.filtersKeyPath
        let selected = filters[keyPath: keyPath]
        if isSelected(option, in: filters) {
            filters[keyPath: keyPath].removeAll { option.values.contains($0) }
        } else {
            filters[keyPath: keyPath] = selected + option.values.filter { !selected.contains($0) }
        }
    }

    public static func facetCount(_ option: FilterOption, facets: [String: [String: Int]]) -> Int? {
        guard let values = facets[option.group.facetKey] else { return nil }
        return option.values.reduce(0) { $0 + (values[$1] ?? 0) }
    }

    public static func activeCount(_ filters: SearchFilters) -> Int {
        FilterGroup.allCases.reduce(0) { count, group in
            let agencyCodes = group == .agency ? filters.agency : []
            return count + options(in: group, agencyCodes: agencyCodes)
                .filter { isSelected($0, in: filters) }
                .count
        }
    }

    private static func option(_ id: String, group: FilterGroup, values: [String]) -> FilterOption {
        FilterOption(
            id: id,
            titleKey: "search.filter.option.\(id)",
            values: values,
            group: group
        )
    }
}

public struct BrowseCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let titleKey: String
    public let values: [String]
}

public enum SearchSort: String, CaseIterable, Identifiable, Sendable {
    case relevance
    case closeDate
    case newest
    case awardCeiling
    case title

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .relevance: return "search.sort.relevance"
        case .closeDate: return "search.sort.close_date"
        case .newest: return "search.sort.newest"
        case .awardCeiling: return "search.sort.award_ceiling"
        case .title: return "search.sort.title"
        }
    }

    public var sortOrder: [SGModels.SortOrder] {
        let (field, direction): (String, String)
        switch self {
        case .relevance: (field, direction) = ("relevancy", "descending")
        case .closeDate: (field, direction) = ("close_date", "ascending")
        case .newest: (field, direction) = ("post_date", "descending")
        case .awardCeiling: (field, direction) = ("award_ceiling", "descending")
        case .title: (field, direction) = ("opportunity_title", "ascending")
        }
        return [SGModels.SortOrder(orderBy: field, sortDirection: direction)]
    }

    public init?(sortOrder: [SGModels.SortOrder]) {
        guard let sort = sortOrder.first else { return nil }
        switch (sort.orderBy, sort.sortDirection) {
        case ("relevancy", "descending"): self = .relevance
        case ("close_date", "ascending"): self = .closeDate
        case ("post_date", "descending"): self = .newest
        case ("award_ceiling", "descending"): self = .awardCeiling
        case ("opportunity_title", "ascending"): self = .title
        default: return nil
        }
    }
}

public enum QuickStatus: String, CaseIterable, Identifiable, Sendable {
    case open
    case closingSoon
    case forecasted

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .open: return "search.quick.open"
        case .closingSoon: return "search.quick.closing_soon"
        case .forecasted: return "search.quick.forecasted"
        }
    }
}
