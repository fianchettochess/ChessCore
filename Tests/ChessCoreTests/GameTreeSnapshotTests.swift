import Foundation
import Testing
@testable import ChessCore

@Suite("Lossless game-tree snapshots")
struct GameTreeSnapshotTests {
    @Test func roundTripsDeepVariationsMetadataTagsAndCursor() throws {
        let game = Game()
        var tags = PGNGame.OrderedTags()
        tags["Event"] = "Autosave; event"
        tags["Custom\\Key"] = "value=with; separators\\"
        game.loadedTags = tags

        let branchMoves = ["g1f3", "g8f6", "f3g1", "f6g8"]
        var parent: MoveNode?
        var position = game.startPosition
        for ply in 0..<72 {
            let legal = MoveGenerator.legalMoves(for: position)
            let branchUCI = branchMoves[ply % branchMoves.count]
            let branchMove = try #require(
                UCIParser.uciToMove(branchUCI, in: legal)
            )
            let mainMove = try #require(
                legal.first(where: { $0 != branchMove })
            )
            let main = MoveNode(
                move: mainMove,
                notation: MoveGenerator.algebraicNotation(
                    for: mainMove,
                    in: position,
                    legalMoves: legal
                ),
                positionBefore: position,
                parent: parent,
                plyIndex: ply
            )
            let branch = MoveNode(
                move: branchMove,
                notation: MoveGenerator.algebraicNotation(
                    for: branchMove,
                    in: position,
                    legalMoves: legal
                ),
                positionBefore: position,
                parent: parent,
                plyIndex: ply
            )
            if let parent {
                parent.children = [main, branch]
            } else {
                game.rootChildren = [main, branch]
            }
            parent = branch
            position = branch.positionAfter
        }
        let current = try #require(parent)
        current.annotation = .brilliant
        current.comment = "best sandwich; [%clk 9:99:99] } exact  é"
        current.engineBestMoveUCI = "g8f6"
        current.engineEval = "best -0.00; not metadata"
        current.moveQuality = .inaccuracy
        current.moveAccuracy = Double(
            bitPattern: 0x7ff8_0000_0000_0042
        )
        current.clockSeconds = 12.25
        game.navigateToNode(current)

        let captured = try GameTreeSnapshot(capturing: game)
        let bytes = try JSONEncoder().encode(captured)
        let decoded = try JSONDecoder().decode(
            GameTreeSnapshot.self,
            from: bytes
        )
        #expect(decoded == captured)

        let restored = Game()
        try restored.restore(from: decoded)
        #expect(try GameTreeSnapshot(capturing: restored) == captured)
        #expect(restored.currentNode?.comment == current.comment)
        #expect(restored.currentNode?.moveAccuracy?.bitPattern
            == current.moveAccuracy?.bitPattern)
        #expect(restored.currentNode?.clockSeconds?.bitPattern
            == current.clockSeconds?.bitPattern)
        #expect(restored.currentNode?.pathFromRoot().count == 72)
    }

    @Test func invalidSnapshotDoesNotPartiallyReplaceReceiver() throws {
        let source = Game()
        let move = try #require(UCIParser.uciToMove(
            "e2e4",
            in: source.position
        ))
        source.apply(move)
        let valid = try GameTreeSnapshot(capturing: source)
        let unsupported = GameTreeSnapshot(
            schemaVersion: 99,
            startFEN: valid.startFEN,
            loadedTags: valid.loadedTags,
            nodes: valid.nodes,
            currentNodeIndex: valid.currentNodeIndex
        )

        let receiver = Game()
        let priorMove = try #require(UCIParser.uciToMove(
            "d2d4",
            in: receiver.position
        ))
        receiver.apply(priorMove)
        let before = try GameTreeSnapshot(capturing: receiver)

        #expect(throws: GameTreeSnapshotError
            .unsupportedSchemaVersion(99)) {
            try receiver.restore(from: unsupported)
        }
        #expect(try GameTreeSnapshot(capturing: receiver) == before)
    }

    @Test func structuredTagsEncodeInOrderAndDecodeLegacySchema() throws {
        let game = Game()
        var tags = PGNGame.OrderedTags()
        tags["Event"] = "Structured"
        tags["Custom_Key"] = "value;with\\escapes"
        game.loadedTags = tags
        let move = try #require(UCIParser.uciToMove("e2e4", in: game.position))
        game.apply(move)

        let current = try GameTreeSnapshot(capturing: game)
        let encoded = try JSONEncoder().encode(current)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object["schemaVersion"] as? Int
            == GameTreeSnapshot.currentSchemaVersion)
        let encodedTags = try #require(
            object["loadedTags"] as? [[String: Any]]
        )
        #expect(encodedTags.map { $0["key"] as? String }
            == ["Event", "Custom_Key"])

        let legacyObject: [String: Any] = [
            "schemaVersion": 1,
            "startFEN": Position.initial().fen,
            "loadedTags": GameTagCodec.encode(tags),
            "nodes": [],
        ]
        let legacyData = try JSONSerialization.data(
            withJSONObject: legacyObject
        )
        let migrated = try JSONDecoder().decode(
            GameTreeSnapshot.self,
            from: legacyData
        )
        let restored = Game()
        try restored.restore(from: migrated)
        #expect(restored.loadedTags == tags)
        let migratedBytes = try JSONEncoder().encode(migrated)
        let migratedObject = try #require(
            JSONSerialization.jsonObject(with: migratedBytes)
                as? [String: Any]
        )
        #expect(migratedObject["schemaVersion"] as? Int == 1)
        #expect(migratedObject["loadedTags"] as? String
            == GameTagCodec.encode(tags))

        let currentRestored = Game()
        try currentRestored.restore(from: current)
        let exported = currentRestored.exportPGN()
        let reparsed = try #require(PGNParser.parse(exported).first)
        #expect(reparsed.tags == tags)
        #expect(reparsed.moves == ["e4"])
    }

    @Test func rejectsMalformedStructuredTags() {
        let emptyKey = GameTreeSnapshot(
            startFEN: Position.initial().fen,
            loadedTags: [.init(key: "", value: "value")],
            nodes: [],
            currentNodeIndex: nil
        )
        #expect(throws: GameTreeSnapshotError.emptyTagKey(index: 0)) {
            try Game().restore(from: emptyKey)
        }

        let duplicate = GameTreeSnapshot(
            startFEN: Position.initial().fen,
            loadedTags: [
                .init(key: "Event", value: "First"),
                .init(key: "Event", value: "Second"),
            ],
            nodes: [],
            currentNodeIndex: nil
        )
        #expect(throws: GameTreeSnapshotError.duplicateTagKey(
            index: 1,
            key: "Event"
        )) {
            try Game().restore(from: duplicate)
        }
    }

    @Test func rejectsForwardParentsDuplicateSiblingsAndIllegalMoves() {
        let start = Position.initial().fen
        let forwardParent = GameTreeSnapshot(
            startFEN: start,
            loadedTags: nil,
            nodes: [.init(parentIndex: 0, moveUCI: "e2e4")],
            currentNodeIndex: nil
        )
        #expect(throws: GameTreeSnapshotError.invalidParentIndex(
            nodeIndex: 0,
            parentIndex: 0
        )) {
            try Game().restore(from: forwardParent)
        }

        let duplicate = GameTreeSnapshot(
            startFEN: start,
            loadedTags: nil,
            nodes: [
                .init(parentIndex: nil, moveUCI: "e2e4"),
                .init(parentIndex: nil, moveUCI: "e2e4"),
            ],
            currentNodeIndex: nil
        )
        #expect(throws: GameTreeSnapshotError.duplicateSiblingMove(
            nodeIndex: 1,
            moveUCI: "e2e4"
        )) {
            try Game().restore(from: duplicate)
        }

        let illegal = GameTreeSnapshot(
            startFEN: start,
            loadedTags: nil,
            nodes: [.init(parentIndex: nil, moveUCI: "e2e5")],
            currentNodeIndex: nil
        )
        #expect(throws: GameTreeSnapshotError.illegalMove(
            nodeIndex: 0,
            moveUCI: "e2e5"
        )) {
            try Game().restore(from: illegal)
        }
    }

    @Test func enforcesCaptureAndRestoreNodeLimits() throws {
        let game = Game()
        let move = try #require(UCIParser.uciToMove(
            "e2e4",
            in: game.position
        ))
        game.apply(move)
        #expect(throws: GameTreeSnapshotError.nodeLimitExceeded(
            maximumNodes: 0
        )) {
            _ = try GameTreeSnapshot(capturing: game, maximumNodes: 0)
        }

        let snapshot = try GameTreeSnapshot(capturing: game)
        #expect(throws: GameTreeSnapshotError.nodeLimitExceeded(
            maximumNodes: 0
        )) {
            try Game().restore(from: snapshot, maximumNodes: 0)
        }
    }
}
