import Testing
@testable import ChessCore

/// Parsing standard UCI engine output.
///
/// The engines produce standard UCI; the parser is what must not misread it.
/// These cases pin the fields UCI defines as running to the END OF LINE —
/// `string`, `refutation` and `currline` — because scanning past them turns
/// free text into engine data.
struct UCIOutputParserTests {

    @Test("a normal search line parses its fields")
    func normalSearchLine() throws {
        let info = try #require(UCIOutputParser.parseInfo(
            "info depth 20 seldepth 28 multipv 1 score cp 34 nodes 12345 nps 900 pv e2e4 e7e5"
        ))
        #expect(info.depth == 20)
        #expect(info.multipv == 1)
        #expect(info.scoreCp == 34)
        #expect(info.nps == 900)
        #expect(info.pv == ["e2e4", "e7e5"])
    }

    @Test("`info string` is free text, never engine fields")
    func infoStringIsNotParsed() {
        // The damaging case: a string that happens to contain scoring
        // vocabulary must not become an evaluation.
        #expect(UCIOutputParser.parseInfo("info string score cp 999 depth 40") == nil)
        #expect(UCIOutputParser.parseInfo("info string fallback pv e2e4 is unavailable") == nil)
        #expect(UCIOutputParser.parseInfo(
            "info string NNUE evaluation using nn-c288c895ea92.nnue enabled"
        ) == nil)
    }

    @Test("a string appended to a real line cannot alter what came before it")
    func stringDoesNotOverwriteEarlierFields() throws {
        let info = try #require(UCIOutputParser.parseInfo(
            "info depth 12 score cp 20 pv e2e4 string score cp 999"
        ))
        #expect(info.depth == 12)
        #expect(info.scoreCp == 20)
        // `pv` already runs to end of line, so the trailing words stay in it;
        // what matters is that the score was not replaced by the string's.
        #expect(info.pv.first == "e2e4")
    }

    @Test("refutation and currline carry move lists, not fields")
    func moveListFieldsTerminate() {
        #expect(UCIOutputParser.parseInfo("info refutation e2e4 e7e5") == nil)
        #expect(UCIOutputParser.parseInfo("info currline 1 e2e4 e7e5") == nil)
    }

    @Test("bounded scores are discarded, and only as whole tokens")
    func boundedScores() {
        #expect(UCIOutputParser.parseInfo("info depth 5 score cp 30 lowerbound") == nil)
        #expect(UCIOutputParser.parseInfo("info depth 5 score cp 30 upperbound") == nil)
        // A move that merely spells the word is not a bound.
        #expect(UCIOutputParser.parseInfo("info depth 5 score cp 30 pv lowerbound") != nil)
    }

    @Test("score-only and mate probes still parse; progress ticks do not")
    func probesAndNoise() throws {
        let mate = try #require(UCIOutputParser.parseInfo("info depth 0 score mate 0"))
        #expect(mate.mateIn == 0)
        #expect(UCIOutputParser.parseInfo("info depth 20 currmove e2e4 currmovenumber 5") == nil)
    }

    @Test("bestmove, with ponder and with (none)")
    func bestMove() {
        #expect(UCIOutputParser.parseBestMove("bestmove e2e4 ponder e7e5") == "e2e4")
        #expect(UCIOutputParser.parseBestMove("bestmove (none)") == nil)
        #expect(UCIOutputParser.parseBestMove("readyok") == nil)
    }
}
