import XCTest
@testable import ChessCore

/// The evaluation must go out in the spelling every other tool reads, and the
/// spelling this library used to write must keep coming back in.
///
/// `PGNExporter` emitted the clock as `[%clk 0:03:00]` — the bracketed command
/// syntax the PGN specification reserves and Lichess, ChessBase, SCID and
/// python-chess all implement — and then, in the SAME comment block, wrote the
/// evaluation BARE as `+0.34`. So a Fianchetto export handed every reader in
/// the world a legible clock and an evaluation only Fianchetto could see.
///
/// The reader is the risk, not the writer: there are ~2,900 games already
/// stored as move text in the old spelling, plus every file exported before
/// today. Both directions are asserted here, and each assertion is paired with
/// a minimally different control so that neither passes on a dead feature.
final class PGNEvalCommandTests: XCTestCase {

    // MARK: - Writing: the standard spelling

    func testExportWritesTheEvalAsTheReservedCommand() {
        guard let game = PGNParser.loadGame(from: "1. e4 e5 2. Nf3 *") else {
            XCTFail("setup PGN must load"); return
        }
        game.mainLine[0].engineEval = "+0.34"
        game.mainLine[0].clockSeconds = 180
        game.mainLine[0].engineBestMoveUCI = "e2e4"
        game.mainLine[1].engineEval = "-1.42"
        game.mainLine[2].engineEval = "M3"

        // The unwrapped move text: `export` hard-wraps at 80 columns, which can
        // split a long comment between `[%eval` and its argument. Both readers
        // here match `\s+` after the key so the wrap is harmless, but asserting
        // against the wrapped text would be asserting about the wrapper.
        let exported = PGNExporter.moveText(for: game.rootChildren)

        XCTAssertTrue(exported.contains("[%eval +0.34]"),
                      "the evaluation must use the reserved command syntax, got: \(exported)")
        XCTAssertFalse(exported.contains("{[%clk 0:03:00] +0.34"),
                       "…and must no longer sit bare beside the clock, got: \(exported)")
        XCTAssertTrue(exported.contains("[%clk 0:03:00]"),
                      "control: the clock keeps its command spelling")
        XCTAssertTrue(exported.contains("[%eval -1.42]"))
        XCTAssertTrue(exported.contains("best e4"),
                      "control: the best move is NOT a reserved command and stays as prose")
        XCTAssertTrue(exported.contains("[%eval #3]"),
                      "a mate distance is spelled `#3`, not `M3`, got: \(exported)")
    }

    /// A mate whose distance was not recoverable is stored as a bare `M` /
    /// `-M`, and `[%eval #]` is not a thing. Inventing a distance to fill the
    /// command would publish a fact about the position that nothing measured,
    /// so these keep the byte-for-byte form the exporter has always written.
    ///
    /// PRE-EXISTING AND UNCHANGED BY THIS COMMIT, recorded here rather than
    /// left to be rediscovered: the bare distance-less mate does not round-trip
    /// and never did. The reader requires an evaluation token to contain a
    /// digit — the rule that keeps the Informant symbols `+-` / `-+` as prose —
    /// so `{-M}` comes back as a comment, not an evaluation. The `M3` control
    /// below is the same code path WITH a digit, and shows the reader is alive.
    func testMateWithoutADistanceStaysBare() {
        guard let game = PGNParser.loadGame(from: "1. e4 e5 *") else {
            XCTFail("setup PGN must load"); return
        }
        game.mainLine[0].engineEval = "-M"
        game.mainLine[1].engineEval = "M3"

        let exported = PGNExporter.moveText(for: game.rootChildren)
        XCTAssertTrue(exported.contains("{-M}"),
                      "no command spelling exists for a distance-less mate, got: \(exported)")
        XCTAssertTrue(exported.contains("[%eval #3]"),
                      "control: a mate that HAS a distance does get the command spelling")

        guard let reloaded = PGNParser.loadGame(from: "[Result \"*\"]\n\n\(exported) *") else {
            XCTFail("export must re-import"); return
        }
        XCTAssertNil(reloaded.mainLine[0].engineEval,
                     "unchanged pre-existing gap: a digit-less eval token reads as prose")
        XCTAssertEqual(reloaded.mainLine[0].comment, "-M")
        XCTAssertEqual(reloaded.mainLine[1].engineEval, "M3",
                       "control: the mate WITH a distance survives the round trip")
    }

    func testEvalCommandArgumentAcceptsOnlyWhatTheCommandCanSpell() {
        XCTAssertEqual(PGNParser.evalCommandArgument(for: "+0.34"), "+0.34")
        XCTAssertEqual(PGNParser.evalCommandArgument(for: "-1.42"), "-1.42")
        XCTAssertEqual(PGNParser.evalCommandArgument(for: "0.00"), "0.00")
        XCTAssertEqual(PGNParser.evalCommandArgument(for: "M3"), "#3")
        XCTAssertEqual(PGNParser.evalCommandArgument(for: "-M12"), "#-12")
        // Not spellable: no distance on the mate, no decimal point on the
        // number, or not an evaluation at all.
        XCTAssertNil(PGNParser.evalCommandArgument(for: "M"))
        XCTAssertNil(PGNParser.evalCommandArgument(for: "-M"))
        XCTAssertNil(PGNParser.evalCommandArgument(for: "+1"))
        XCTAssertNil(PGNParser.evalCommandArgument(for: "+-"))
        XCTAssertNil(PGNParser.evalCommandArgument(for: ""))
    }

    // MARK: - Reading: the old bare spelling must not stop parsing

    /// MANDATORY, not optional. The owner has ~2,900 games whose stored move
    /// text is in the bare spelling, and every file this app exported before
    /// today is too. If the reader ever narrows to the command form, this is
    /// what says so.
    func testPreviouslyExportedBareEvalsStillParse() {
        // Exactly what `PGNExporter` produced before this change: clock in the
        // command form, evaluation bare, best move and prose after semicolons.
        let legacy = """
        [Result "*"]

        1. e4 {[%clk 0:03:00] +0.34; best e4; solid} e5 {-1.42; best Nf3} 2. Nf3 {M3} *
        """
        guard let game = PGNParser.loadGame(from: legacy) else {
            XCTFail("previously exported PGN must still load"); return
        }
        XCTAssertEqual(game.mainLine[0].engineEval, "+0.34")
        XCTAssertEqual(game.mainLine[0].clockSeconds, 180)
        XCTAssertEqual(game.mainLine[0].comment, "solid")
        XCTAssertEqual(game.mainLine[1].engineEval, "-1.42")
        XCTAssertEqual(game.mainLine[2].engineEval, "M3")

        // The same fields read out of the NEW spelling, so "the old form still
        // parses" is not being satisfied by a reader that has stopped reading
        // evaluations altogether.
        let current = """
        [Result "*"]

        1. e4 {[%clk 0:03:00] [%eval +0.34]; best e4; solid} e5 {[%eval -1.42]; best Nf3} 2. Nf3 {[%eval #3]} *
        """
        guard let modern = PGNParser.loadGame(from: current) else {
            XCTFail("current-spelling PGN must load"); return
        }
        XCTAssertEqual(modern.mainLine[0].engineEval, "+0.34")
        XCTAssertEqual(modern.mainLine[0].clockSeconds, 180)
        XCTAssertEqual(modern.mainLine[0].comment, "solid")
        XCTAssertEqual(modern.mainLine[1].engineEval, "-1.42")
        XCTAssertEqual(modern.mainLine[2].engineEval, "M3")
    }

    /// Export → import, on the writer's own output, for the values that make up
    /// almost every annotated ply.
    func testEvalSurvivesTheFullRoundTrip() {
        guard let game = PGNParser.loadGame(from: "1. e4 e5 2. Nf3 *") else {
            XCTFail("setup PGN must load"); return
        }
        game.mainLine[0].engineEval = "+0.34"
        game.mainLine[0].clockSeconds = 180
        game.mainLine[0].comment = "solid"
        game.mainLine[1].engineEval = "-1.42"
        game.mainLine[2].engineEval = "M3"

        guard let reloaded = PGNParser.loadGame(from: PGNExporter.export(game: game)) else {
            XCTFail("export must re-import"); return
        }
        XCTAssertEqual(reloaded.mainLine[0].engineEval, "+0.34")
        XCTAssertEqual(reloaded.mainLine[0].clockSeconds, 180)
        XCTAssertEqual(reloaded.mainLine[0].comment, "solid")
        XCTAssertEqual(reloaded.mainLine[1].engineEval, "-1.42")
        XCTAssertEqual(reloaded.mainLine[2].engineEval, "M3")
    }
}
