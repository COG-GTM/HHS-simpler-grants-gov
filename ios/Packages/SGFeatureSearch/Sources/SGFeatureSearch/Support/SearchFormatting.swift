import Foundation
import SGModels

public enum SearchFormatting {
    public static func fullCurrency(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

    public static func compactCurrency(_ value: Int) -> String {
        let magnitude = abs(Double(value))
        if magnitude >= 1_000_000 {
            return compactSuffix(Double(value) / 1_000_000, suffix: "M")
        }
        if magnitude >= 1_000 {
            return compactSuffix(Double(value) / 1_000, suffix: "K")
        }
        return fullCurrency(value)
    }

    public static func awardRange(floor: Int?, ceiling: Int?) -> String {
        switch (floor.flatMap { $0 > 0 ? $0 : nil }, ceiling.flatMap { $0 > 0 ? $0 : nil }) {
        case let (floor?, ceiling?):
            return "\(compactCurrency(floor))–\(compactCurrency(ceiling))"
        case let (nil, ceiling?):
            return String(format: "search.format.up_to".localized(bundle: .module), compactCurrency(ceiling))
        case let (floor?, nil):
            return String(format: "search.format.from".localized(bundle: .module), compactCurrency(floor))
        case (nil, nil):
            return "—"
        }
    }

    public static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = utcCalendar
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter.string(from: date)
    }

    public static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = utcCalendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func compactSuffix(_ value: Double, suffix: String) -> String {
        let rounded = (value * 10).rounded() / 10
        let number = rounded.rounded() == rounded
            ? String(format: "%.0f", locale: Locale(identifier: "en_US"), rounded)
            : String(format: "%.1f", locale: Locale(identifier: "en_US"), rounded)
        return "$\(number)\(suffix)"
    }
}

public enum OpportunityDisplayStatus: Equatable, Sendable {
    case open
    case closingSoon(daysLeft: Int)
    case forecasted
    case closed

    public static func resolve(_ opportunity: Opportunity, now: Date) -> Self {
        switch opportunity.opportunityStatus {
        case .forecasted:
            return .forecasted
        case .closed, .archived:
            return .closed
        case .posted:
            guard let daysLeft = daysLeft(for: opportunity, now: now) else { return .open }
            if daysLeft < 0 { return .closed }
            if daysLeft <= 14 { return .closingSoon(daysLeft: daysLeft) }
            return .open
        }
    }

    public static func daysLeft(for opportunity: Opportunity, now: Date) -> Int? {
        guard let closeDate = opportunity.summary.closeDateValue else { return nil }
        let calendar = SearchFormatting.utcCalendar
        let start = calendar.startOfDay(for: now)
        let close = calendar.startOfDay(for: closeDate)
        return calendar.dateComponents([.day], from: start, to: close).day
    }

    public var statusChipKey: String {
        switch self {
        case .open: return "open"
        case .closingSoon: return "closing_soon"
        case .forecasted: return "forecasted"
        case .closed: return "closed"
        }
    }
}

public enum HTMLText {
    public static func plainText(from html: String) -> String {
        var text = html
        for (pattern, replacement) in [
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</(p|div|li)\\s*>", "\n"),
            ("(?i)<li\\b[^>]*>", "• ")
        ] {
            text = replacing(pattern, in: text, with: replacement)
        }
        text = replacing("<[^>]+>", in: text, with: "")
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        text = decodeNumericEntities(in: text)
        text = replacing("\\n{3,}", in: text, with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        value.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: .regularExpression
        )
    }

    private static func decodeNumericEntities(in value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") else { return value }
        let source = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
        var result = value
        for match in matches.reversed() {
            let entity = source.substring(with: match.range(at: 1))
            let number: UInt32?
            if entity.lowercased().hasPrefix("x") {
                number = UInt32(entity.dropFirst(), radix: 16)
            } else {
                number = UInt32(entity, radix: 10)
            }
            guard let number, let scalar = UnicodeScalar(number) else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: String(scalar))
        }
        return result
    }
}
