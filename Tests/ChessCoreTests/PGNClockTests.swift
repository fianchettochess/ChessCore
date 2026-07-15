import XCTest
@testable import ChessCore

/// Guards `[%clk ...]` parsing after C2 replaced the per-call
/// `range(of:options:.regularExpression)` + `Scanner` with a compiled static
/// regex + capture groups. Match semantics must stay byte-identical to the
/// original `\[%clk\s+(\d+):(\d{2}):(\d{2}(?:\.\d+)?)\]` pattern.
final class PGNClockTests: XCTestCase {
    func testClockSecondsParsing() {
        XCTAssertEqual(PGNParser.parseEngineComment("[%clk 1:30:05]").clockSeconds, 5405)
        XCTAssertEqual(PGNParser.parseEngineComment("[%clk 0:05:00]").clockSeconds, 300)
        XCTAssertEqual(PGNParser.parseEngineComment("[%clk 0:05:00.5]").clockSeconds, 300.5)
        // Multi-digit hours are allowed (\d+); minutes/seconds are exactly \d{2}.
        XCTAssertEqual(PGNParser.parseEngineComment("[%clk 12:00:00]").clockSeconds, 43200)
        // 1-digit minutes/seconds fail the \d{2} groups → no match.
        XCTAssertNil(PGNParser.parseEngineComment("[%clk 5:5:5]").clockSeconds)
        // No whitespace after `clk` fails \s+ → no match.
        XCTAssertNil(PGNParser.parseEngineComment("[%clk0:05:00]").clockSeconds)
        // No clock tag at all.
        XCTAssertNil(PGNParser.parseEngineComment("+1.2; best Nf3").clockSeconds)
    }
}
