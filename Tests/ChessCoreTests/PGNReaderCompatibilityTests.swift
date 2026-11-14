import XCTest
import CryptoKit
@testable import ChessCore

/// Gates stored game identity against tokenizer, tag and replay refactors. A
/// changed token, annotation, branch or tag would duplicate or corrupt a row.
/// Literal values were captured on unmodified 0.17.1 (06ae8ee), before fixes.
final class PGNReaderCompatibilityTests: XCTestCase {
    struct Golden: Codable {
        let name: String
        let input: String
        let tokens: String
        let tags: String
        let moves: [String]
        let result: String?
        let resultText: String
        let tree: String
        let exported: String
        let contentID: String
        let authoredID: String
        let moveTextHash: String
    }

    // A test-only transcription of FianchettoKit GameData.swift's unstripped
    // GameDedup wire (length-prefixed UTF-8, token kinds, sorted non-mirror tags).
    // These fixtures are balanced and contain no legacy best-move markers.
    private func identity(_ game: PGNGame, excludingLink: Bool) -> String {
        var bytes: [UInt8] = []
        func number(_ value: UInt64) {
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            }
        }
        func string(_ value: String) {
            number(UInt64(value.utf8.count)); bytes += value.utf8
        }
        for value in [game.white, game.black, game.date, game.resultText, game.event, game.opening] { string(value) }
        let tokens = game.moveTokens.filter {
            if case .comment(let text) = $0 { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return true
        }
        bytes.append(0); number(UInt64(tokens.count))
        for token in tokens {
            switch token {
            case .move(let word): bytes.append(0); string(word)
            case .variationStart: bytes.append(1)
            case .variationEnd: bytes.append(2)
            case .comment(let text): bytes.append(3); string(text.trimmingCharacters(in: .whitespacesAndNewlines))
            case .nag(let n): bytes.append(4); number(UInt64(n))
            }
        }
        let mirrors: Set<String> = ["white", "black", "date", "result", "event", "opening", "eco"]
        let keys = game.tags.orderedKeys.filter { key in
            let chars = Array(key.utf8)
            func letter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
            return chars.first.map(letter) == true && chars.dropFirst().allSatisfy { letter($0) || (48...57).contains($0) || $0 == 95 }
                && !mirrors.contains(key.lowercased()) && !(excludingLink && key.lowercased() == "link")
        }.sorted()
        number(UInt64(keys.count))
        for key in keys { string(key); string(game.tags[key] ?? "") }
        return (excludingLink ? "authored-content:v1:" : "content:v2:") + digest(Data(bytes))
    }

    private func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func capture(_ name: String, _ input: String) throws -> Golden {
        let parsed = try XCTUnwrap(PGNParser.parse(input).first, name)
        let game = try XCTUnwrap(PGNParser.loadGame(from: parsed), name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let tree = String(decoding: try encoder.encode(GameTreeSnapshot(capturing: game)), as: UTF8.self)
        let text = PGNExporter.tokenText(from: parsed)
        return Golden(name: name, input: input, tokens: text, tags: GameTagCodec.encode(parsed.tags),
                      moves: parsed.moves, result: parsed.result, resultText: parsed.resultText,
                      tree: tree, exported: PGNExporter.moveText(for: game.rootChildren),
                      contentID: identity(parsed, excludingLink: false), authoredID: identity(parsed, excludingLink: true),
                      moveTextHash: digest(Data(text.utf8)))
    }

    func testAccepted0171GamesKeepLiteralTreesTokensTagsAndHashesSoReimportsCannotDuplicateRows() throws {
        let cases = try JSONDecoder().decode([Golden].self, from: Data(Self.golden0171.utf8))
        XCTAssertEqual(cases.count, 18)
        for expected in cases {
            let actual = try capture(expected.name, expected.input)
            XCTAssertEqual(actual.tokens, expected.tokens, expected.name)
            XCTAssertEqual(actual.tags, expected.tags, expected.name)
            XCTAssertEqual(actual.moves, expected.moves, expected.name)
            XCTAssertEqual(actual.result, expected.result, expected.name)
            XCTAssertEqual(actual.resultText, expected.resultText, expected.name)
            XCTAssertEqual(actual.tree, expected.tree, expected.name)
            XCTAssertEqual(actual.exported, expected.exported, expected.name)
            XCTAssertEqual(actual.contentID, expected.contentID, expected.name)
            XCTAssertEqual(actual.authoredID, expected.authoredID, expected.name)
            XCTAssertEqual(actual.moveTextHash, expected.moveTextHash, expected.name)
        }
    }
    // The two existing payloads come from PGNNAGBoundTests and
    // PGNEvalCommandTests. Provider samples are representative additions;
    // 0.17.1 has no provider-named fixture files.
    private static let golden0171 = #"""
[
  {
    "authoredID" : "authored-content:v1:c8ca6ec31f457009513a88ae5e5738afe558f6476f75a23e96127d7dd52c2c0b",
    "contentID" : "content:v2:c8ca6ec31f457009513a88ae5e5738afe558f6476f75a23e96127d7dd52c2c0b",
    "exported" : "1. e4! c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be3 e5",
    "input" : "[Event \"Club Championship\"]\n[Site \"?\"]\n[Date \"2009.03.14\"]\n[Round \"4\"]\n[White \"Hall, R.\"]\n[Black \"Okafor, T.\"]\n[Result \"1-0\"]\n\n1. e4 $1 c5 2. Nf3 d6 $14 3. d4 cxd4 4. Nxd4 $18 Nf6 5. Nc3 $146 a6 $300\n6. Be3 $99999999999999999999 e5 1-0",
    "moveTextHash" : "44282f0bdb595eba21bf636e5cefc04a72a4c047acb88a4e5b4d909b63cf0a79",
    "moves" : [
      "e4",
      "c5",
      "Nf3",
      "d6",
      "d4",
      "cxd4",
      "Nxd4",
      "Nf6",
      "Nc3",
      "a6",
      "Be3",
      "$99999999999999999999",
      "e5"
    ],
    "name" : "existing-club-ChessBase-style",
    "result" : "1-0",
    "resultText" : "1-0",
    "tags" : "Event=Club Championship;Site=?;Date=2009.03.14;Round=4;White=Hall, R.;Black=Okafor, T.;Result=1-0",
    "tokens" : "e4 $1 c5 Nf3 d6 $14 d4 cxd4 Nxd4 $18 Nf6 Nc3 $146 a6 $300 Be3 $99999999999999999999 e5",
    "tree" : "{\"currentNodeIndex\":11,\"nodes\":[{\"annotationRawValue\":\"!\",\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"c7c5\",\"parentIndex\":0},{\"moveUCI\":\"g1f3\",\"parentIndex\":1},{\"moveUCI\":\"d7d6\",\"parentIndex\":2},{\"moveUCI\":\"d2d4\",\"parentIndex\":3},{\"moveUCI\":\"c5d4\",\"parentIndex\":4},{\"moveUCI\":\"f3d4\",\"parentIndex\":5},{\"moveUCI\":\"g8f6\",\"parentIndex\":6},{\"moveUCI\":\"b1c3\",\"parentIndex\":7},{\"moveUCI\":\"a7a6\",\"parentIndex\":8},{\"moveUCI\":\"c1e3\",\"parentIndex\":9},{\"moveUCI\":\"e7e5\",\"parentIndex\":10}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:3739b5296ca1813e021b03d4ec66fd3723ecfadf3da8f72046103d7555d23a10",
    "contentID" : "content:v2:3739b5296ca1813e021b03d4ec66fd3723ecfadf3da8f72046103d7555d23a10",
    "exported" : "1. e4 {[%clk 0:03:00] [%eval +0.34]; best e4; solid} e5 {[%eval -1.42]; best Nf3} 2. Nf3 {[%eval #3]}",
    "input" : "[Result \"*\"]\n\n1. e4 {[%clk 0:03:00] +0.34; best e4; solid} e5 {-1.42; best Nf3} 2. Nf3 {M3} *",
    "moveTextHash" : "cc47e7312c5cc636282dd4781255ee5d793815ccf75f0ec296e43b227f62b230",
    "moves" : [
      "e4",
      "e5",
      "Nf3"
    ],
    "name" : "existing-legacy-evals",
    "result" : "*",
    "resultText" : "*",
    "tags" : "Result=*",
    "tokens" : "e4 {[%clk 0:03:00] +0.34; best e4; solid} e5 {-1.42; best Nf3} Nf3 {M3}",
    "tree" : "{\"currentNodeIndex\":2,\"nodes\":[{\"clockSecondsBitPattern\":4640537203540230144,\"comment\":\"solid\",\"engineBestMoveUCI\":\"e2e4\",\"engineEval\":\"+0.34\",\"moveUCI\":\"e2e4\"},{\"engineBestMoveUCI\":\"Nf3\",\"engineEval\":\"-1.42\",\"moveUCI\":\"e7e5\",\"parentIndex\":0},{\"engineEval\":\"M3\",\"moveUCI\":\"g1f3\",\"parentIndex\":1}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:56894c5a31479df6892fe6fbebbe45e2315d655145384ee2ac83a4d80da8c68c",
    "contentID" : "content:v2:56894c5a31479df6892fe6fbebbe45e2315d655145384ee2ac83a4d80da8c68c",
    "exported" : "1. e4 {[%clk 0:03:00] [%eval 0.22]} e5 {[%clk 0:02:59]} 2. Nf3 Nc6",
    "input" : "[Event \"Rated Blitz game\"]\n[Site \"https://lichess.org/Ab12Cd34\"]\n[Date \"2024.03.14\"]\n[White \"Alice\"]\n[Black \"Bob\"]\n[Result \"1/2-1/2\"]\n[TimeControl \"180+2\"]\n\n1. e4 {[%eval 0.22] [%clk 0:03:00]} e5 {[%clk 0:02:59]} 2. Nf3 Nc6 1/2-1/2",
    "moveTextHash" : "5a7cc131a9c9fe2045656d63458c02ab5a0ad67a05008850ec0bcc85b32821a6",
    "moves" : [
      "e4",
      "e5",
      "Nf3",
      "Nc6"
    ],
    "name" : "Lichess-style",
    "result" : "1/2-1/2",
    "resultText" : "1/2-1/2",
    "tags" : "Event=Rated Blitz game;Site=https://lichess.org/Ab12Cd34;Date=2024.03.14;White=Alice;Black=Bob;Result=1/2-1/2;TimeControl=180+2",
    "tokens" : "e4 {[%eval 0.22] [%clk 0:03:00]} e5 {[%clk 0:02:59]} Nf3 Nc6",
    "tree" : "{\"currentNodeIndex\":3,\"nodes\":[{\"clockSecondsBitPattern\":4640537203540230144,\"engineEval\":\"0.22\",\"moveUCI\":\"e2e4\"},{\"clockSecondsBitPattern\":4640502019168141312,\"moveUCI\":\"e7e5\",\"parentIndex\":0},{\"moveUCI\":\"g1f3\",\"parentIndex\":1},{\"moveUCI\":\"b8c6\",\"parentIndex\":2}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:f33693e604a16d37faf84b86d56bd2b9fb99eed18c4ad36e5c83dfb500e99fab",
    "contentID" : "content:v2:7aaf19ceffdefc477aac39c4db9f974120b6032a07365fbd550bda3623ac21e5",
    "exported" : "1. d4 {[%clk 0:09:58]} d5 2. c4 e6 ( 2... c6! {Slav} ) 3. Nc3 Nf6",
    "input" : "[Event \"Live Chess\"]\n[Site \"Chess.com\"]\n[Date \"2023.06.02\"]\n[Round \"-\"]\n[White \"Alice\"]\n[Black \"Bob\"]\n[Result \"1-0\"]\n[Link \"https://www.chess.com/game/live/123456789\"]\n\n1. d4 {[%clk 0:09:58]} d5 2. c4 e6 (2... c6 $1 {Slav}) 3. Nc3 Nf6 1-0",
    "moveTextHash" : "b35217cff92647a38a37df334a9e53a74ab82f637c0d2637703a1770ae8ecd37",
    "moves" : [
      "d4",
      "d5",
      "c4",
      "e6",
      "Nc3",
      "Nf6"
    ],
    "name" : "chess.com-style",
    "result" : "1-0",
    "resultText" : "1-0",
    "tags" : "Event=Live Chess;Site=Chess.com;Date=2023.06.02;Round=-;White=Alice;Black=Bob;Result=1-0;Link=https://www.chess.com/game/live/123456789",
    "tokens" : "d4 {[%clk 0:09:58]} d5 c4 e6 ( c6 $1 {Slav} ) Nc3 Nf6",
    "tree" : "{\"currentNodeIndex\":5,\"nodes\":[{\"clockSecondsBitPattern\":4648471279446261760,\"moveUCI\":\"d2d4\"},{\"moveUCI\":\"d7d5\",\"parentIndex\":0},{\"moveUCI\":\"c2c4\",\"parentIndex\":1},{\"moveUCI\":\"e7e6\",\"parentIndex\":2},{\"moveUCI\":\"b1c3\",\"parentIndex\":3},{\"moveUCI\":\"g8f6\",\"parentIndex\":4},{\"annotationRawValue\":\"!\",\"comment\":\"Slav\",\"moveUCI\":\"c7c6\",\"parentIndex\":2}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:7ee102382363ebd68cd5302b3a613b79d90de7c557531475ae30ac8597dd3032",
    "contentID" : "content:v2:7ee102382363ebd68cd5302b3a613b79d90de7c557531475ae30ac8597dd3032",
    "exported" : "1. e4! c5 2. Nf3 d6 ( 2... Nc6!? {Alternative} 3. d4 ) 3. d4 cxd4 4. Nxd4",
    "input" : "[Event \"City Championship\"]\n[Site \"London\"]\n[Date \"2011.11.05\"]\n[Round \"3\"]\n[White \"Hall, R.\"]\n[Black \"Okafor, T.\"]\n[Result \"*\"]\n[Annotator \"Coach\"]\n\n1. e4 $1 c5 2. Nf3 d6 (2... Nc6 $5 {Alternative} 3. d4) 3. d4 cxd4 4. Nxd4 *",
    "moveTextHash" : "25b2c14b00d8283a518f18a77a284fc24ee1e68b8b3ed8b7ad90d091d3720e24",
    "moves" : [
      "e4",
      "c5",
      "Nf3",
      "d6",
      "d4",
      "cxd4",
      "Nxd4"
    ],
    "name" : "ChessBase-style",
    "result" : "*",
    "resultText" : "*",
    "tags" : "Event=City Championship;Site=London;Date=2011.11.05;Round=3;White=Hall, R.;Black=Okafor, T.;Result=*;Annotator=Coach",
    "tokens" : "e4 $1 c5 Nf3 d6 ( Nc6 $5 {Alternative} d4 ) d4 cxd4 Nxd4",
    "tree" : "{\"currentNodeIndex\":6,\"nodes\":[{\"annotationRawValue\":\"!\",\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"c7c5\",\"parentIndex\":0},{\"moveUCI\":\"g1f3\",\"parentIndex\":1},{\"moveUCI\":\"d7d6\",\"parentIndex\":2},{\"moveUCI\":\"d2d4\",\"parentIndex\":3},{\"moveUCI\":\"c5d4\",\"parentIndex\":4},{\"moveUCI\":\"f3d4\",\"parentIndex\":5},{\"annotationRawValue\":\"!?\",\"comment\":\"Alternative\",\"moveUCI\":\"b8c6\",\"parentIndex\":2},{\"moveUCI\":\"d2d4\",\"parentIndex\":7}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:2b7581d90f5009c4ea2447aeaa306b94f394ca93ca8e85f1fabbe8191084858a",
    "contentID" : "content:v2:2b7581d90f5009c4ea2447aeaa306b94f394ca93ca8e85f1fabbe8191084858a",
    "exported" : "1. e4 ( 1. d4 d5 2. c4 ) e5",
    "input" : "1. e4 (1 d4 d5 2 c4) e5",
    "moveTextHash" : "5bbc155f869ee8534732b95b084b01097f212361b60483729bb7a0419d68137c",
    "moves" : [
      "e4",
      "e5"
    ],
    "name" : "bare-variation",
    "resultText" : "*",
    "tags" : "",
    "tokens" : "e4 ( 1 d4 d5 2 c4 ) e5",
    "tree" : "{\"currentNodeIndex\":1,\"nodes\":[{\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"e7e5\",\"parentIndex\":0},{\"moveUCI\":\"d2d4\"},{\"moveUCI\":\"d7d5\",\"parentIndex\":2},{\"moveUCI\":\"c2c4\",\"parentIndex\":3}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:8860893e580a1fa7e3bd39fb7443092fdb3ebad1bbade3aab7f28312a785ac1d",
    "contentID" : "content:v2:8860893e580a1fa7e3bd39fb7443092fdb3ebad1bbade3aab7f28312a785ac1d",
    "exported" : "1. e4 e5",
    "input" : "[Result \"1-0\"]\n\n1. e4 e5 ½-½",
    "moveTextHash" : "f809522c9acb50c2d6d9f10fbe3d6c24c428cc94bc24c27e8cb29d7c629b5352",
    "moves" : [
      "e4",
      "e5",
      "½-½"
    ],
    "name" : "half-point",
    "resultText" : "1-0",
    "tags" : "Result=1-0",
    "tokens" : "e4 e5 ½-½",
    "tree" : "{\"currentNodeIndex\":1,\"nodes\":[{\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"e7e5\",\"parentIndex\":0}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:b1f62aef37d359d96dbce038d5fb8aeb0c17f3b019db61aea195306b8f447ace",
    "contentID" : "content:v2:b1f62aef37d359d96dbce038d5fb8aeb0c17f3b019db61aea195306b8f447ace",
    "exported" : "1. e4 Nf6",
    "input" : "1. e4 -- 2. d4 Nf6 *",
    "moveTextHash" : "3bd0c8e69eade61d9eee1046332bab91d9a26cfd3f08c5336bef3e97941ecb35",
    "moves" : [
      "e4",
      "--",
      "d4",
      "Nf6"
    ],
    "name" : "null-dash",
    "result" : "*",
    "resultText" : "*",
    "tags" : "",
    "tokens" : "e4 -- d4 Nf6",
    "tree" : "{\"currentNodeIndex\":1,\"nodes\":[{\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"g8f6\",\"parentIndex\":0}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:6e2d5a948e8ea330d291910337a540de22ccbe91bd2806723411e8d6efb5f812",
    "contentID" : "content:v2:6e2d5a948e8ea330d291910337a540de22ccbe91bd2806723411e8d6efb5f812",
    "exported" : "1. e4 Nf6",
    "input" : "1. e4 Z0 2. d4 Nf6 *",
    "moveTextHash" : "c29146e9ee9a44fb9c397419ac94a189be2cd8bad999c36bfa917b79320573c5",
    "moves" : [
      "e4",
      "Z0",
      "d4",
      "Nf6"
    ],
    "name" : "null-Z0",
    "result" : "*",
    "resultText" : "*",
    "tags" : "",
    "tokens" : "e4 Z0 d4 Nf6",
    "tree" : "{\"currentNodeIndex\":1,\"nodes\":[{\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"g8f6\",\"parentIndex\":0}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:1fd665bc98138f9dd68106803dc922f30379126236c210353496bcb91e515bb4",
    "contentID" : "content:v2:1fd665bc98138f9dd68106803dc922f30379126236c210353496bcb91e515bb4",
    "exported" : "1. e4 e5",
    "input" : "[A \"1\"][B \"2\"]\n1. e4 e5 *",
    "moveTextHash" : "74f4a316c6253603e721bfb5cb6c993a72c7eb8dad80e190ff01b8c8e00f7573",
    "moves" : [
      "e4",
      "e5"
    ],
    "name" : "adjacent-tags",
    "result" : "*",
    "resultText" : "*",
    "tags" : "A=1;B=2",
    "tokens" : "e4 e5",
    "tree" : "{\"currentNodeIndex\":1,\"nodes\":[{\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"e7e5\",\"parentIndex\":0}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:bf08d5d86d4afe62209fb60fe5540d09ebfc37b118a4e1171da054fee50acf2e",
    "contentID" : "content:v2:bf08d5d86d4afe62209fb60fe5540d09ebfc37b118a4e1171da054fee50acf2e",
    "exported" : "1. e4 e5",
    "input" : "﻿% encoding note\n[Event \"Imported\"]\n1. e4\n% hidden {\ne5 *",
    "moveTextHash" : "74f4a316c6253603e721bfb5cb6c993a72c7eb8dad80e190ff01b8c8e00f7573",
    "moves" : [
      "e4",
      "e5"
    ],
    "name" : "BOM-escape",
    "result" : "*",
    "resultText" : "*",
    "tags" : "Event=Imported",
    "tokens" : "e4 e5",
    "tree" : "{\"currentNodeIndex\":1,\"nodes\":[{\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"e7e5\",\"parentIndex\":0}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:7350650743113d5526c63f2d27adfeb6859d1bf49ce5c186fb8036e233f58129",
    "contentID" : "content:v2:7350650743113d5526c63f2d27adfeb6859d1bf49ce5c186fb8036e233f58129",
    "exported" : "1. e4! e5 2. Nf3 Nc6 3. Bb5 Nf6",
    "input" : "1. e4$1 1…e5 2. Nf3 Nc6 3. Bb5 ...Nf6+- *",
    "moveTextHash" : "3d1dbc7a9b5017020fae757ceb82537c3c79b23a3790e78e288ade3b82c70e43",
    "moves" : [
      "e4$1",
      "1…e5",
      "Nf3",
      "Nc6",
      "Bb5",
      "...Nf6+-"
    ],
    "name" : "attached",
    "result" : "*",
    "resultText" : "*",
    "tags" : "",
    "tokens" : "e4$1 1…e5 Nf3 Nc6 Bb5 ...Nf6+-",
    "tree" : "{\"currentNodeIndex\":5,\"nodes\":[{\"annotationRawValue\":\"!\",\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"e7e5\",\"parentIndex\":0},{\"moveUCI\":\"g1f3\",\"parentIndex\":1},{\"moveUCI\":\"b8c6\",\"parentIndex\":2},{\"moveUCI\":\"f1b5\",\"parentIndex\":3},{\"moveUCI\":\"g8f6\",\"parentIndex\":4}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:28bafa9f8954b26910d0868f1215ce689c2b724ecf89247ecd02498775df2924",
    "contentID" : "content:v2:28bafa9f8954b26910d0868f1215ce689c2b724ecf89247ecd02498775df2924",
    "exported" : "1. e4 d5 2. exd5",
    "input" : "1. e4 d5 2. d5",
    "moveTextHash" : "44d5d9575de9654aa0d8766f6057a149ea0f3e2ddfa4c1982f126f6a7e002a50",
    "moves" : [
      "e4",
      "d5",
      "d5"
    ],
    "name" : "inferred-capture",
    "resultText" : "*",
    "tags" : "",
    "tokens" : "e4 d5 d5",
    "tree" : "{\"currentNodeIndex\":2,\"nodes\":[{\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"d7d5\",\"parentIndex\":0},{\"moveUCI\":\"e4d5\",\"parentIndex\":1}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:d905db8d53ce26b1fb28f6d66aa0d1191d05dac24b8485ff0c06e4b69a22e4eb",
    "contentID" : "content:v2:d905db8d53ce26b1fb28f6d66aa0d1191d05dac24b8485ff0c06e4b69a22e4eb",
    "exported" : "1. a8=Q#",
    "input" : "[FEN 8/P7/8/8/8/8/8/k1K5 w - - 0 1]\n1. a8/Q *",
    "moveTextHash" : "b528898759de1df70a3cf03d8d78fb8bc4400b3c4f650714e90be545909a8b00",
    "moves" : [
      "a8/Q"
    ],
    "name" : "unquoted-FEN",
    "result" : "*",
    "resultText" : "*",
    "tags" : "FEN=8/P7/8/8/8/8/8/k1K5 w - - 0 1",
    "tokens" : "a8/Q",
    "tree" : "{\"currentNodeIndex\":0,\"nodes\":[{\"moveUCI\":\"a7a8q\"}],\"schemaVersion\":2,\"startFEN\":\"8/P7/8/8/8/8/8/k1K5 w - - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:eb30f0fb805fe25c6fec7e83041d6bfbafe4435c84f51f1784392dd9e08e84f0",
    "contentID" : "content:v2:eb30f0fb805fe25c6fec7e83041d6bfbafe4435c84f51f1784392dd9e08e84f0",
    "exported" : "1. e5 Nf3",
    "input" : "[FEN \"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 23\"]\n23... e5 24. Nf3 *",
    "moveTextHash" : "706c622c782404c6812538b3d75203c1770e4f241642e0bec2a5d2c9de621aa1",
    "moves" : [
      "e5",
      "Nf3"
    ],
    "name" : "Black-start",
    "result" : "*",
    "resultText" : "*",
    "tags" : "FEN=rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 23",
    "tokens" : "e5 Nf3",
    "tree" : "{\"currentNodeIndex\":1,\"nodes\":[{\"moveUCI\":\"e7e5\"},{\"moveUCI\":\"g1f3\",\"parentIndex\":0}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 23\"}"
  },
  {
    "authoredID" : "authored-content:v1:f3376959ecbaaae937e05bd4b5f34f647ebed2a0e92537ae27637960fdb07568",
    "contentID" : "content:v2:f3376959ecbaaae937e05bd4b5f34f647ebed2a0e92537ae27637960fdb07568",
    "exported" : "1. e4 e5 2. Nf3 Nc6",
    "input" : "1. e4 e5\n[diagram]\n2. Nf3 Nc6",
    "moveTextHash" : "c15ae45de814c704b2d73d71672b7edd3f611056b14f9d9225f1c57f1c45ee0f",
    "moves" : [
      "e4",
      "e5",
      "[diagram]",
      "Nf3",
      "Nc6"
    ],
    "name" : "bracket-note",
    "resultText" : "*",
    "tags" : "",
    "tokens" : "e4 e5 [diagram] Nf3 Nc6",
    "tree" : "{\"currentNodeIndex\":3,\"nodes\":[{\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"e7e5\",\"parentIndex\":0},{\"moveUCI\":\"g1f3\",\"parentIndex\":1},{\"moveUCI\":\"b8c6\",\"parentIndex\":2}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:51f6de41b0afe7e836c6c617e0c0399babb6a1357e8382e47123ecc0fa627c85",
    "contentID" : "content:v2:51f6de41b0afe7e836c6c617e0c0399babb6a1357e8382e47123ecc0fa627c85",
    "exported" : "1. e4 e5",
    "input" : "1. e4 e5\n\n[diagram]\n\n2. Nf3",
    "moveTextHash" : "74f4a316c6253603e721bfb5cb6c993a72c7eb8dad80e190ff01b8c8e00f7573",
    "moves" : [
      "e4",
      "e5"
    ],
    "name" : "bracket-blank",
    "resultText" : "*",
    "tags" : "",
    "tokens" : "e4 e5",
    "tree" : "{\"currentNodeIndex\":1,\"nodes\":[{\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"e7e5\",\"parentIndex\":0}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  },
  {
    "authoredID" : "authored-content:v1:7043dd4375c52f7620dfd63fcce0b2bcde099c0dcb1cac61d4e4e8692a37824b",
    "contentID" : "content:v2:7043dd4375c52f7620dfd63fcce0b2bcde099c0dcb1cac61d4e4e8692a37824b",
    "exported" : "1. e4 e5 2. Nf3 ( 2. Bc4 Nf6 ( 2... Bc5 3. c3 ) ( 2... d6 ) 3. d3 ) Nc6",
    "input" : "1. e4 e5 2. Nf3 (2. Bc4 (2... Bc5 3. c3) (2... d6) 2... Nf6 3. d3) Nc6",
    "moveTextHash" : "3637a3dd4731dd8528b1282c56357b6e15322424db594f503ff2112f1ed60db6",
    "moves" : [
      "e4",
      "e5",
      "Nf3",
      "Nc6"
    ],
    "name" : "nested",
    "resultText" : "*",
    "tags" : "",
    "tokens" : "e4 e5 Nf3 ( Bc4 ( Bc5 c3 ) ( d6 ) Nf6 d3 ) Nc6",
    "tree" : "{\"currentNodeIndex\":3,\"nodes\":[{\"moveUCI\":\"e2e4\"},{\"moveUCI\":\"e7e5\",\"parentIndex\":0},{\"moveUCI\":\"g1f3\",\"parentIndex\":1},{\"moveUCI\":\"b8c6\",\"parentIndex\":2},{\"moveUCI\":\"f1c4\",\"parentIndex\":1},{\"moveUCI\":\"g8f6\",\"parentIndex\":4},{\"moveUCI\":\"d2d3\",\"parentIndex\":5},{\"moveUCI\":\"f8c5\",\"parentIndex\":4},{\"moveUCI\":\"c2c3\",\"parentIndex\":7},{\"moveUCI\":\"d7d6\",\"parentIndex\":4}],\"schemaVersion\":2,\"startFEN\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"}"
  }
]
"""#
}
