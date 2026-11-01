import XCTest
@testable import ChessCore

final class PGNDefaultDateTests: XCTestCase {
    func testDefaultDateResistsBuddhistCalendarAndNonEnglishLocaleSoConsumersSeeGregorianYear() throws {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .autoupdatingCurrent
        let date = try XCTUnwrap(localCalendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12)))

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.calendar = Calendar(identifier: .buddhist)
        formatter.timeZone = TimeZone(secondsFromGMT: 14 * 3600)!
        PGNExporter.configurePGNDateFormatter(formatter)

        XCTAssertEqual(formatter.string(from: date), "2026.10.30")
        XCTAssertEqual(formatter.locale.identifier, "en_US_POSIX")
        XCTAssertEqual(formatter.calendar.identifier, .gregorian)
        XCTAssertEqual(formatter.timeZone.secondsFromGMT(for: date), TimeZone.current.secondsFromGMT(for: date))
        XCTAssertEqual(PGNExporter.defaultTags(for: Game(), date: date)["Date"], "2026.10.30")
    }
}
