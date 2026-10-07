import Foundation
import SGCore
import SGModels

public enum ApplyCTA {
    case startApplication(Competition)
    case applyOnGrantsGov(URL)
    case signInToApply
    case closed
    case notYetOpen

    public static func resolve(detail: OpportunityDetail, session: SessionState, now: Date) -> Self {
        switch OpportunityDisplayStatus.resolve(detail.opportunity, now: now) {
        case .closed:
            return .closed
        case .forecasted:
            return .notYetOpen
        case .open, .closingSoon:
            if let competition = detail.competitions.first(where: { $0.isOpen && $0.isSimplerGrantsEnabled }) {
                if case .signedIn = session {
                    return .startApplication(competition)
                }
                return .signInToApply
            }
            return .applyOnGrantsGov(grantsGovURL(for: detail))
        }
    }

    public static func shareURL(opportunityId: String) -> URL {
        URL(string: "https://simpler.grants.gov/opportunity/\(opportunityId)")!
    }

    private static func grantsGovURL(for detail: OpportunityDetail) -> URL {
        if let legacyId = detail.opportunity.legacyOpportunityId {
            return URL(string: "https://www.grants.gov/search-results-detail/\(legacyId)")!
        }
        guard let number = detail.opportunityNumber, !number.isEmpty else {
            return URL(string: "https://www.grants.gov/search-grants")!
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.subtract(CharacterSet(charactersIn: "&=+#?"))
        let encoded = number.addingPercentEncoding(withAllowedCharacters: allowed) ?? number
        return URL(string: "https://www.grants.gov/search-grants?keywords=\(encoded)")!
    }
}
