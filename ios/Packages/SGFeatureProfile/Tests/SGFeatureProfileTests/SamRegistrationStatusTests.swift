import Foundation
import XCTest
@testable import SGFeatureProfile

final class SamRegistrationStatusTests: XCTestCase {
    private var today: Date { Self.date("2026-10-07") }

    func testExpirationBoundaries() {
        XCTAssertEqual(
            SamRegistrationStatus.evaluate(expirationDate: "2026-12-07", today: today),
            .active(expires: Self.date("2026-12-07"))
        )
        XCTAssertEqual(
            SamRegistrationStatus.evaluate(expirationDate: "2026-12-06", today: today),
            .expiringSoon(expires: Self.date("2026-12-06"), daysRemaining: 60)
        )
        XCTAssertEqual(
            SamRegistrationStatus.evaluate(expirationDate: "2026-10-08", today: today),
            .expiringSoon(expires: Self.date("2026-10-08"), daysRemaining: 1)
        )
        XCTAssertEqual(
            SamRegistrationStatus.evaluate(expirationDate: "2026-10-07", today: today),
            .expiringSoon(expires: Self.date("2026-10-07"), daysRemaining: 0)
        )
        XCTAssertEqual(
            SamRegistrationStatus.evaluate(expirationDate: "2026-10-06", today: today),
            .expired(expiredOn: Self.date("2026-10-06"))
        )
    }

    func testMissingAndInvalidExpirationDatesAreUnknown() {
        XCTAssertEqual(SamRegistrationStatus.evaluate(expirationDate: nil, today: today), .unknown)
        XCTAssertEqual(SamRegistrationStatus.evaluate(expirationDate: "garbage", today: today), .unknown)
        XCTAssertEqual(SamRegistrationStatus.evaluate(expirationDate: "2026-02-30", today: today), .unknown)
    }

    func testISO8601TimestampUsesItsDatePrefix() {
        XCTAssertEqual(
            SamRegistrationStatus.evaluate(
                expirationDate: "2027-03-01T00:00:00Z",
                today: today
            ),
            .active(expires: Self.date("2027-03-01"))
        )
    }

    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)!
    }
}
