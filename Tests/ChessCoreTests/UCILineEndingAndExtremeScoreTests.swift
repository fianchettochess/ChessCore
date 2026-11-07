import Foundation
import Testing
@testable import ChessCore

/// Engine output from hosts other than the bundled engines.
///
/// Gates three things:
/// - CRLF output. Line splitting at `\n` leaves a `\r` glued to the last
///   token. Dropping the terminator trim in `UCIOutputParser.parseInfo` or
///   `parseBestMove` (or reintroducing a strict length check before it)
///   silently discards every score and bestmove from such an engine: the user
///   sees an analysis pane that never fills in.
/// - Stored moves decode as written. `UCIParser.uciToMove` also restores
///   snapshot nodes, so it does not trim. Adding the trim there by accident
///   (it looks like the same fix) makes a stored `"e2e4\r"` node that 0.16.1
///   refused restore as e2e4, and lets `"e2e4"` and `"e2e4\r"` restore as two
///   identical sibling moves: the user's restored game differs from what any
///   other version restores.
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

    @Test("bestmove with a CR or CRLF names the same move",
          arguments: [
              ("bestmove e2e4\r", "e2e4"),
              ("bestmove e2e4 ponder e7e5\r\n", "e2e4"),
              ("bestmove (none)\r", nil),
          ] as [(String, String?)])
    func bestMoveTerminators(line: String, expected: String?) {
        #expect(UCIOutputParser.parseBestMove(line) == expected)
    }

    @Test("a coordinate move with any trailing character, including CR, selects no move",
          arguments: [
              ("e2e4", "e2e4\r"),
              ("e2e4", "e2e4\n"),
              ("e2e4", "e2e4\r\n"),
              ("e2e4", "e2e4 "),
              ("e2e4", "e2e4x\r"),
              ("e7e8q", "e7e8q\r"),
          ])
    func uciMoveTerminator(legal: String, written: String) throws {
        let position = try #require(Position(
            fen: legal == "e7e8q" ? "8/4P3/8/8/8/8/k7/4K3 w - - 0 1" : Position.initial().fen
        ))
        #expect(UCIParser.uciToMove(legal, in: position) != nil)
        #expect(UCIParser.uciToMove(written, in: position) == nil)
    }

    /// Golden: stored snapshot payloads with a CR-suffixed `moveUCI`. The
    /// expected errors are what 0.16.1 throws for these exact bytes.
    @Test("a stored snapshot node with a CR-suffixed move restores exactly as in 0.16.1",
          arguments: [
              (#"{"schemaVersion":2,"startFEN":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","loadedTags":null,"nodes":[{"moveUCI":"e2e4\r"}],"currentNodeIndex":0}"#,
               GameTreeSnapshotError.illegalMove(nodeIndex: 0, moveUCI: "e2e4\r")),
              (#"{"schemaVersion":2,"startFEN":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","loadedTags":null,"nodes":[{"moveUCI":"e2e4"},{"moveUCI":"e2e4\r"}],"currentNodeIndex":0}"#,
               .illegalMove(nodeIndex: 1, moveUCI: "e2e4\r")),
          ])
    func storedCRSuffixedMove(json: String, expected: GameTreeSnapshotError) throws {
        let snapshot = try JSONDecoder().decode(GameTreeSnapshot.self, from: Data(json.utf8))
        let game = Game()
        #expect(throws: expected) { try game.restore(from: snapshot) }
        #expect(game.rootChildren.isEmpty)
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
