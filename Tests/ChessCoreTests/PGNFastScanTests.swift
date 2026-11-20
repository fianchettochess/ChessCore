import XCTest
@testable @_spi(FastScanAudit) import ChessCore

// Gates the ASCII byte tokenizer behind `PGNParser.tokenize` (pgn-fast-scan).
// Tokens feed stored-game identity in FianchettoKit (canonical move text and
// content keys); a scanner that read one move text differently would re-key
// games. Every input must tokenize exactly as the Character scanner does,
// including the adversarial ones the fast path is meant to hand back.
final class PGNFastScanTests: XCTestCase {
    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    private static let pieces: [String] = [
        "1.", "1...", "12.", "e4", "e5", "Nf3", "Nc6", "O-O", "O-O-O", "exd5", "e8=Q+", "Qxf7#", "Rae1!?", "Bb5?!",
        " ", "  ", "\t", "\n", "\r", "\r\n", "\u{0B}", "\u{0C}", "(", ")", "((", "{", "}", "{comment}", "{a}b}",
        ";", "; best Nf3\n", "%", "\n%escape\n", "$1", "$+3", "$-2", "$", "$99999999999999999999", "$x",
        "1-0", "0-1", "1/2-1/2", "*", "½-½", "…", "1…", "e4…", "é", "e\u{0301}", "\u{FEFF}", "\u{00A0}", "\u{2028}",
        "\u{0085}", "\u{001C}", "\u{001F}", "\u{0000}", "\u{007F}", "\u{037E}", "１", "٣", "\"", "[", "]", "..", "1..",
    ]

    static func corpus(count: Int) -> [String] {
        var generator = Generator(state: 0xFA57)
        var out = ["", " ", "{", "}", "(", ")", ";", "%", "1.", "1. e4 e5 2. Nf3 {unterminated", "%x", "a\n%b\nc"]
        for _ in 0..<count {
            let length = generator.next(24)
            out.append((0..<length).map { _ in pieces[generator.next(pieces.count)] }.joined())
        }
        return out
    }

    func testFastScanMatchesTheCharacterScannerOnAnAdversarialCorpus() {
        var fast = 0, mismatches: [String] = []
        for text in Self.corpus(count: 120_000) {
            if PGNParser.asciiTokens(text) != nil { fast += 1 }
            if !PGNParser.fastScanAgrees(text) { mismatches.append(text) }
        }
        print("PGN_FAST_SCAN checked=\(120_012) fast=\(fast) mismatches=\(mismatches.count)")
        XCTAssertEqual(mismatches.count, 0, "\(mismatches.prefix(10).map { String(reflecting: $0) })")
        XCTAssertGreaterThan(fast, 10_000)
    }

    /// Set PGN_FAST_SCAN_CORPUS to a directory to compare every *.pgn, *.json
    /// and *.txt file's text (and each JSON string value) as move text.
    func testFastScanMatchesOnAnExternalCorpus() throws {
        guard let root = ProcessInfo.processInfo.environment["PGN_FAST_SCAN_CORPUS"] else { return }
        var checked = 0, mismatches = 0
        let enumerator = FileManager.default.enumerator(atPath: root)
        while let path = enumerator?.nextObject() as? String {
            guard ["pgn", "json", "txt"].contains((path as NSString).pathExtension) else { continue }
            guard let data = FileManager.default.contents(atPath: root + "/" + path),
                  let text = String(data: data, encoding: .utf8) else { continue }
            var inputs = [text]
            if path.hasSuffix(".json"), let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                func walk(_ value: Any) {
                    if let string = value as? String { inputs.append(string) }
                    else if let array = value as? [Any] { array.forEach(walk) }
                    else if let object = value as? [String: Any] { object.values.forEach(walk) }
                }
                walk(json)
            }
            for input in inputs {
                checked += 1
                if !PGNParser.fastScanAgrees(input) { mismatches += 1 }
            }
        }
        print("PGN_FAST_SCAN_EXTERNAL checked=\(checked) mismatches=\(mismatches)")
        XCTAssertEqual(mismatches, 0)
    }
}
