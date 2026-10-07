import Foundation
import SGDesign
import SwiftUI

public enum SamRegistrationStatus: Equatable, Sendable {
    case active(expires: Date)
    case expiringSoon(expires: Date, daysRemaining: Int)
    case expired(expiredOn: Date)
    case unknown

    public static let expiringWindowDays = 60

    public static func evaluate(
        expirationDate: String?,
        today: Date,
        calendar: Calendar = .samUTC
    ) -> SamRegistrationStatus {
        guard
            let expirationDate,
            expirationDate.count >= 10,
            let expiration = parseDate(String(expirationDate.prefix(10)))
        else {
            return .unknown
        }

        let todayStart = calendar.startOfDay(for: today)
        let expirationStart = calendar.startOfDay(for: expiration)
        guard let days = calendar.dateComponents([.day], from: todayStart, to: expirationStart).day else {
            return .unknown
        }

        if days < 0 {
            return .expired(expiredOn: expirationStart)
        }
        if days <= expiringWindowDays {
            return .expiringSoon(expires: expirationStart, daysRemaining: days)
        }
        return .active(expires: expirationStart)
    }

    public var localizedText: String {
        switch self {
        case let .active(expires):
            return String(
                format: "profile.sam.active".localized(bundle: .module),
                locale: Locale(identifier: "en_US"),
                Self.format(expires, format: "MMM yyyy")
            )
        case let .expiringSoon(expires, daysRemaining):
            let key = daysRemaining == 1 ? "profile.sam.expiring_one_day" : "profile.sam.expiring_days"
            return String(
                format: key.localized(bundle: .module),
                locale: Locale(identifier: "en_US"),
                Self.format(expires, format: "MMM d, yyyy"),
                daysRemaining
            )
        case let .expired(expiredOn):
            return String(
                format: "profile.sam.expired".localized(bundle: .module),
                locale: Locale(identifier: "en_US"),
                Self.format(expiredOn, format: "MMM d, yyyy")
            )
        case .unknown:
            return "profile.sam.unknown".localized(bundle: .module)
        }
    }

    var iconName: String {
        switch self {
        case .active: "checkmark.seal.fill"
        case .expiringSoon: "exclamationmark.triangle.fill"
        case .expired: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var tintColor: Color {
        switch self {
        case .active: SG.C.green
        case .expiringSoon: SG.C.foreFg
        case .expired: SG.C.red
        case .unknown: SG.C.muted
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    private static func format(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

public extension Calendar {
    static var samUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
