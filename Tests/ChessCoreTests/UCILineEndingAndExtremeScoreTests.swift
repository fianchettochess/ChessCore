import Testing
@testable import ChessCore

/// Engine output from hosts other than the bundled engines.
///
/// Gates two things a face that hosts a third-party engine depends on:
/// - CRLF output. Line splitting at `\n` leaves a `\r` glued to the last
///   token. Dropping the terminator trim (or reintroducing a strict length
///   check before it) silently discards every score and bestmove from such an
///   engine: the user sees an analysis pane that never fills in.
/// - Extreme scores. A buggy or hostile engine can report `Int.min`.
///   `abs(Int.min)` and `-Int.min` trap, so reverting to either crashes the
///   app while it formats or flips the evaluation.
struct UCILineEndingAndExtremeScoreTests {

    @Test("a trailing CR or CRLF does not change what an engine line parses to",
          arguments: [
              "info depth 20 multipv 1 score cp 30 nps 900 pv e2e4 e7e5",
              "info depth 18 score cp -45 pv d2d4",
              "info depth 7 score mate -3 pv h7h8q",
              "info depth 0 score mate 0",
          ])
    func infoLineTerminators(line: String) throws {
        let plain = try #require(UCIOutputParser.parseInfo(line))
        #expect(UCIOutputParser.parseInfo(line + "\r") == plain)
        #expect(UCIOutputParser.parseInfo(line + "\r\n") == plain)
    }

    @Test("bestmove with a CR names the same move")
    func bestMoveTerminators() {
        #expect(UCIOutputParser.parseBestMove("bestmove e2e4\r") == "e2e4")
        #expect(UCIOutputParser.parseBestMove("bestmove e2e4 ponder e7e5\r\n") == "e2e4")
        #expect(UCIOutputParser.parseBestMove("bestmove (none)\r") == nil)
    }

    @Test("a coordinate move with a trailing CR selects the same legal move; other trailing text still fails")
    func uciMoveTerminator() throws {
        let start = Position.initial()
        let e4 = try #require(UCIParser.uciToMove("e2e4", in: start))
        #expect(UCIParser.uciToMove("e2e4\r", in: start) == e4)
        #expect(UCIParser.uciToMove("e2e4\r\n", in: start) == e4)
        #expect(UCIParser.uciToMove("e2e4 ", in: start) == nil)
        #expect(UCIParser.uciToMove("e2e4x\r", in: start) == nil)
        let promotion = try #require(Position(fen: "8/4P3/8/8/8/8/k7/4K3 w - - 0 1"))
        #expect(UCIParser.uciToMove("e7e8q\r", in: promotion)?.promotion == .queen)
    }

    /// Golden: the sign the engine wrote is the sign the parser keeps.
    @Test("negative centipawn and mate scores keep their sign")
    func signKept() throws {
        let cp = try #require(UCIOutputParser.parseInfo("info depth 18 score cp -45 pv d2d4"))
        #expect(cp.scoreCp == -45)
        #expect(cp.displayText == "-0.4")
        let mate = try #require(UCIOutputParser.parseInfo("info depth 7 score mate -3 pv h7h8q"))
        #expect(mate.mateIn == -3)
        #expect(mate.displayText == "-M3")
    }

    @Test("Int.min and Int.max scores format and negate without trapping",
          arguments: [
              (UCIInfo.Score.cp(.min), "-92233720368547758.0", UCIInfo.Score.cp(.max)),
              (.mate(.min), "-M9223372036854775808", .mate(.max)),
              (.cp(.max), "+92233720368547758.0", .cp(-.max)),
              (.mate(.max), "M9223372036854775807", .mate(-.max)),
          ])
    func extremeScores(score: UCIInfo.Score, text: String, negated: UCIInfo.Score) {
        #expect(score.displayText == text)
        #expect(score.negated == negated)
    }

    @Test("White-POV conversion of an Int.min score keeps a usable sign")
    func extremeWhitePov() {
        #expect(UCIInfo.whitePovCp(.min, sideToMoveIsWhite: false) == .max)
        #expect(UCIInfo.whitePovMate(.min, sideToMoveIsWhite: false) == .max)
        let info = UCIInfo(scoreCp: .min)
        #expect(info.whitePovCentipawns(sideToMoveIsWhite: false) == .max)
    }
}
