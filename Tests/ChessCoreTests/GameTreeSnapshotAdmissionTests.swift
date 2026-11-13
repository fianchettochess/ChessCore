import Foundation
import Testing
@testable import ChessCore

@Suite("Snapshot writer admission matches deployed readers")
struct GameTreeSnapshotAdmissionTests {
    enum TagSource: CaseIterable {
        case raw, pgn
    }

    private func taggedGame(count: Int, source: TagSource) throws -> Game {
        let game = Game()
        switch source {
        case .raw:
            var tags = PGNGame.OrderedTags()
            for index in 0..<count { tags["K\(index)"] = "value\(index)" }
            game.loadedTags = tags
            game.apply(try #require(UCIParser.uciToMove("e2e4", in: game.position)))
        case .pgn:
            let text = (0..<count).map { "[K\($0) \"value\($0)\"]" }
                .joined(separator: "\n") + "\n\n1. e4 *"
            let parsed = try #require(PGNParser.parse(text).first)
            #expect(game.loadPGNGame(parsed))
        }
        return game
    }

    /// Gates exact, ordered tags from both public ingestion paths. An off-by-one
    /// guard or a prefix-based fix could discard the boundary tag; the user
    /// would lose authored tags or their entire autosaved board on reopening.
    @Test("up to 4,096 tags survive capture, decode and restore exactly",
          arguments: [0, 1, 4_096], TagSource.allCases)
    func acceptedTagsRoundTrip(count: Int, source: TagSource) throws {
        let game = try taggedGame(count: count, source: source)
        let snapshot = try GameTreeSnapshot(capturing: game)
        #expect((snapshot.loadedTags?.count ?? 0) == count)
        #expect(snapshot.loadedTags?.map(\.key)
            == game.loadedTags?.insertionOrderedKeys)
        let decoded = try JSONDecoder().decode(
            GameTreeSnapshot.self, from: JSONEncoder().encode(snapshot)
        )
        #expect(decoded == snapshot)
        let restored = Game()
        try restored.restore(from: decoded)
        #expect(restored.loadedTags == game.loadedTags)
        #expect(try GameTreeSnapshot(capturing: restored) == snapshot)
    }

    /// Gates save-time failure and preservation of the previous file. Moving
    /// validation to decode or silently taking a prefix would let autosave
    /// overwrite recovery data, costing the user their board or exact tag row.
    @Test("4,097 tags fail during capture before an autosave write",
          arguments: TagSource.allCases)
    func excessTagsKeepPreviousAutosave(source: TagSource) throws {
        let game = try taggedGame(count: 4_097, source: source)
        let tagsBefore = game.loadedTags
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chesscore-c91-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let previous = try JSONEncoder().encode(GameTreeSnapshot(capturing: Game()))
        try previous.write(to: url, options: .atomic)
        var captureReturned = false
        #expect(throws: GameTreeSnapshotError.tagLimitExceeded(maximumTags: 4_096)) {
            let snapshot = try GameTreeSnapshot(capturing: game)
            captureReturned = true
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        }
        #expect(!captureReturned)
        #expect(try Data(contentsOf: url) == previous)
        #expect(game.loadedTags == tagsBefore)
    }

    /// Gates the decoder's fixed node ceiling even with a larger caller budget.
    /// Removing the clamp would admit an unreadable save and lose the board;
    /// tightening it accidentally would refuse a previously supported tree.
    @Test("node capture cannot exceed the deployed reader's 65,536-node ceiling",
          arguments: [65_536, 65_537], [65_536, Int.max])
    func nodeBudgetCannotRaiseWireLimit(count: Int, requestedLimit: Int) throws {
        let game = Game()
        let shuffle = ["g1f3", "g8f6", "f3g1", "f6g8"]
        var moves: [Move] = []
        var position = game.startPosition
        for uci in shuffle {
            let move = try #require(UCIParser.uciToMove(uci, in: position))
            moves.append(move)
            MoveGenerator.applyMoveUnchecked(&position, move)
        }
        position = game.startPosition
        var parent: MoveNode?
        for index in 0..<count {
            let node = MoveNode(
                move: moves[index % moves.count], notation: "", positionBefore: position,
                parent: parent, plyIndex: index
            )
            if let parent { parent.children = [node] } else { game.rootChildren = [node] }
            position = node.positionAfter
            parent = node
        }
        if count > 65_536 {
            #expect(throws: GameTreeSnapshotError.nodeLimitExceeded(maximumNodes: 65_536)) {
                _ = try GameTreeSnapshot(capturing: game, maximumNodes: requestedLimit)
            }
        } else {
            let snapshot = try GameTreeSnapshot(capturing: game, maximumNodes: requestedLimit)
            #expect(snapshot.nodes.count == count)
            #expect(try JSONDecoder().decode(
                GameTreeSnapshot.self, from: JSONEncoder().encode(snapshot)
            ) == snapshot)
        }
    }

    /// Gates the unchecked value initializer's encoding escape hatch. If only
    /// capture were guarded, a direct caller could still replace the user's
    /// recovery file with bytes an older reader refuses.
    @Test("direct snapshots also refuse arrays beyond reader limits",
          arguments: [true, false])
    func directEncodingRefusesExcessArrays(tags: Bool) throws {
        let snapshot = GameTreeSnapshot(
            startFEN: Position.initial().fen,
            loadedTags: tags ? (0..<4_097).map { .init(key: "K\($0)", value: "V") } : nil,
            nodes: tags ? [] : Array(repeating: .init(parentIndex: nil, moveUCI: "e2e4"), count: 65_537),
            currentNodeIndex: nil
        )
        let error: GameTreeSnapshotError = tags
            ? .tagLimitExceeded(maximumTags: 4_096)
            : .nodeLimitExceeded(maximumNodes: 65_536)
        #expect(throws: error) { _ = try JSONEncoder().encode(snapshot) }
    }

    /// Gates raw empty keys, which OrderedTags can hold but restore rejects.
    /// Dropping this validation would save a board the user cannot reopen;
    /// filtering the key instead would silently lose the user's original row.
    @Test("capture refuses an empty tag key without editing the model")
    func emptyTagKeyFailsCapture() throws {
        let game = Game()
        var tags = PGNGame.OrderedTags()
        tags[""] = "keep this value"
        game.loadedTags = tags
        #expect(throws: GameTreeSnapshotError.emptyTagKey(index: 0)) {
            _ = try GameTreeSnapshot(capturing: game)
        }
        #expect(game.loadedTags == tags)
    }

    /// Gates optional-tag wire semantics. Coalescing nil into [] during the
    /// admission refactor would change old bytes and the user's stored row.
    @Test("absent and explicitly empty tags stay distinct", arguments: [true, false])
    func absentAndEmptyTagsStayDistinct(absent: Bool) throws {
        let game = Game()
        game.loadedTags = absent ? nil : PGNGame.OrderedTags()
        let snapshot = try GameTreeSnapshot(capturing: game)
        #expect((snapshot.loadedTags == nil) == absent)
        let decoded = try JSONDecoder().decode(
            GameTreeSnapshot.self, from: JSONEncoder().encode(snapshot)
        )
        #expect(decoded == snapshot)
    }

    /// Gates the audit of the other authored fields: annotations are a scalar
    /// enum, and comments/tag strings/engine strings have no snapshot length
    /// bound. Reusing a PGN text cap or trimming these during capture would
    /// discard the user's prose, metadata or glyphs from an otherwise valid save.
    @Test("long strings and every annotation survive without truncation",
          arguments: MoveAnnotation.allCases)
    func unboundedAuthoredFieldsStayExact(annotation: MoveAnnotation) throws {
        let game = Game()
        let text = String(repeating: " é } ; ♞\n", count: 8_193)
        #expect(text.utf8.count > 65_536)
        var tags = PGNGame.OrderedTags()
        tags[text] = text
        game.loadedTags = tags
        game.apply(try #require(UCIParser.uciToMove("e2e4", in: game.position)))
        let node = try #require(game.currentNode)
        node.annotation = annotation
        node.comment = text
        node.engineBestMoveUCI = text
        node.engineEval = text
        let captured = try GameTreeSnapshot(capturing: game)
        let decoded = try JSONDecoder().decode(
            GameTreeSnapshot.self, from: JSONEncoder().encode(captured)
        )
        #expect(decoded == captured)
        let restored = Game()
        try restored.restore(from: decoded)
        #expect(restored.loadedTags == tags)
        #expect(restored.currentNode?.annotation == annotation)
        #expect(restored.currentNode?.comment == text)
        #expect(restored.currentNode?.engineBestMoveUCI == text)
        #expect(restored.currentNode?.engineEval == text)
    }

    /// Gates literal historical bytes and current capture against the same
    /// payload. Rebuilding expectations with today's writer, changing tag
    /// order, or normalizing strings would mask format drift and cost users
    /// older recovery files or their exact authored content.
    @Test("real 0.17.1 payloads decode, re-encode and capture byte-identically",
          arguments: ["GameTreeSnapshot-0.17.1", "GameTreeSnapshot-0.17.1-4096-tags"])
    func historicalGoldenKeepsExactWireBytes(fixture: String) throws {
        let url = try #require(Bundle.module.url(
            forResource: fixture, withExtension: "json", subdirectory: "Fixtures"
        ))
        let bytes = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(GameTreeSnapshot.self, from: bytes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(decoded) == bytes)
        let game = try fixture == "GameTreeSnapshot-0.17.1"
            ? historicalGame() : taggedGame(count: 4_096, source: .raw)
        #expect(try encoder.encode(GameTreeSnapshot(capturing: game)) == bytes)
        let restored = Game()
        try restored.restore(from: decoded)
        #expect(try GameTreeSnapshot(capturing: restored) == decoded)
    }

    private func historicalGame() throws -> Game {
        let game = Game()
        var tags = PGNGame.OrderedTags()
        tags["Custom\\Key"] = "value=with; separators\\\n\" é ♞"
        tags["Event"] = "0.17.1 autosave"
        tags["Empty"] = ""
        game.loadedTags = tags
        func play(_ uci: String) throws {
            game.apply(try #require(UCIParser.uciToMove(uci, in: game.position)))
        }
        try play("e2e4")
        let e4 = try #require(game.currentNode)
        try play("e7e5")
        try play("g1f3")
        game.navigateToNode(e4)
        try play("c7c5")
        let branch = try #require(game.currentNode)
        branch.annotation = .brilliant
        branch.comment = "exact } [%clk 9:99:99]; \\\n é ♞"
        branch.engineBestMoveUCI = "g1f3"
        branch.engineEval = "best -0.00; not metadata"
        branch.moveQuality = .inaccuracy
        branch.moveAccuracy = Double(bitPattern: 0x7ff8_0000_0000_0042)
        branch.clockSeconds = 12.25
        return game
    }
}
