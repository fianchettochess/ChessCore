import XCTest
@testable import ChessCore

final class StreakMathTests: XCTestCase {
    func testCurrentTrailingRun() {
        XCTAssertEqual(StreakMath.current([]), 0)
        XCTAssertEqual(StreakMath.current([true, true, true]), 3)
        XCTAssertEqual(StreakMath.current([true, false, true, true]), 2)
        XCTAssertEqual(StreakMath.current([true, true, false]), 0)
    }

    func testBestRunAnywhere() {
        XCTAssertEqual(StreakMath.best([]), 0)
        XCTAssertEqual(StreakMath.best([true, false, true, true, false, true]), 2)
        XCTAssertEqual(StreakMath.best([true, true, true, true]), 4)
        XCTAssertEqual(StreakMath.best([false, false]), 0)
    }
}
