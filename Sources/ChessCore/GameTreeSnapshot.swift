import Foundation

/// A versioned, lossless, flat representation of a ``Game`` move tree.
///
/// PGN is an interchange and presentation format, not a durable object graph:
/// comments have no escape for `}`, application metadata shares one comment
/// namespace, and defensive PGN exporters may intentionally truncate hostile
/// variation depth. This snapshot keeps authored node fields distinct and uses
/// parent indexes so encoding and decoding do not recurse through the tree.
public nonisolated struct GameTreeSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    /// Practical defense against tiny-object amplification during JSON decode.
    public static let maximumLoadedTagPairs = 4_096

    /// Explicit admission prevents a future schema-version bump from silently
    /// accepting a wire format whose decoder and resource policy are not ready.
    public static func supportsSchemaVersion(_ version: Int) -> Bool {
        switch version {
        case 1, 2: true
        default: false
        }
    }

    /// One ordered PGN tag pair. An array is used instead of a JSON object so
    /// the model's exact tag insertion order survives every encoder.
    public nonisolated struct Tag: Codable, Equatable, Sendable {
        public let key: String
        public let value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public nonisolated struct Node: Codable, Equatable, Sendable {
        public let parentIndex: Int?
        public let moveUCI: String
        public let annotationRawValue: String?
        public let comment: String?
        public let engineBestMoveUCI: String?
        public let engineEval: String?
        public let moveQualityRawValue: String?
        /// IEEE-754 bits preserve finite values, infinities, and NaN payloads
        /// without relying on a JSON encoder's non-conforming-float policy.
        public let moveAccuracyBitPattern: UInt64?
        public let clockSecondsBitPattern: UInt64?

        public init(
            parentIndex: Int?,
            moveUCI: String,
            annotationRawValue: String? = nil,
            comment: String? = nil,
            engineBestMoveUCI: String? = nil,
            engineEval: String? = nil,
            moveQualityRawValue: String? = nil,
            moveAccuracyBitPattern: UInt64? = nil,
            clockSecondsBitPattern: UInt64? = nil
        ) {
            self.parentIndex = parentIndex
            self.moveUCI = moveUCI
            self.annotationRawValue = annotationRawValue
            self.comment = comment
            self.engineBestMoveUCI = engineBestMoveUCI
            self.engineEval = engineEval
            self.moveQualityRawValue = moveQualityRawValue
            self.moveAccuracyBitPattern = moveAccuracyBitPattern
            self.clockSecondsBitPattern = clockSecondsBitPattern
        }
    }

    public let schemaVersion: Int
    public let startFEN: String
    /// `nil` and an explicitly empty tag collection remain distinguishable.
    public let loadedTags: [Tag]?
    public let nodes: [Node]
    public let currentNodeIndex: Int?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        startFEN: String,
        loadedTags: [Tag]?,
        nodes: [Node],
        currentNodeIndex: Int?
    ) {
        self.schemaVersion = schemaVersion
        self.startFEN = startFEN
        self.loadedTags = loadedTags
        self.nodes = nodes
        self.currentNodeIndex = currentNodeIndex
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case startFEN
        case loadedTags
        case nodes
        case currentNodeIndex
    }

    /// Schema 1 encoded tags through `GameTagCodec`. Decode that representation
    /// for crash-recovery migration, while every newly captured snapshot uses
    /// structured schema-2 pairs.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard Self.supportsSchemaVersion(schemaVersion) else {
            throw GameTreeSnapshotError.unsupportedSchemaVersion(schemaVersion)
        }
        startFEN = try values.decode(String.self, forKey: .startFEN)
        currentNodeIndex = try values.decodeIfPresent(
            Int.self,
            forKey: .currentNodeIndex
        )
        if !values.contains(.loadedTags) {
            loadedTags = nil
        } else if try values.decodeNil(forKey: .loadedTags) {
            loadedTags = nil
        } else if schemaVersion == 1 {
            let legacy = try values.decode(String.self, forKey: .loadedTags)
            let decoded = GameTagCodec.decodeOrdered(legacy)
            guard GameTagCodec.encode(decoded) == legacy else {
                throw GameTreeSnapshotError.invalidLegacyTagEncoding
            }
            loadedTags = decoded.insertionOrderedKeys.compactMap { key in
                decoded[key].map { Tag(key: key, value: $0) }
            }
        } else {
            loadedTags = try Self.decodeBoundedArray(
                Tag.self,
                from: values,
                forKey: .loadedTags,
                maximumCount: Self.maximumLoadedTagPairs,
                limitError: .tagLimitExceeded(
                    maximumTags: Self.maximumLoadedTagPairs
                )
            )
        }
        nodes = try Self.decodeBoundedArray(
            Node.self,
            from: values,
            forKey: .nodes,
            maximumCount: PGNParser.maximumMoveTreeNodes,
            limitError: .nodeLimitExceeded(
                maximumNodes: PGNParser.maximumMoveTreeNodes
            )
        )
    }

    private static func decodeBoundedArray<Element: Decodable>(
        _ elementType: Element.Type,
        from values: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        maximumCount: Int,
        limitError: GameTreeSnapshotError
    ) throws -> [Element] {
        var container = try values.nestedUnkeyedContainer(forKey: key)
        if let count = container.count, count > maximumCount {
            throw limitError
        }
        var result: [Element] = []
        result.reserveCapacity(min(container.count ?? 0, maximumCount))
        while !container.isAtEnd {
            guard result.count < maximumCount else { throw limitError }
            result.append(try container.decode(elementType))
        }
        return result
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(startFEN, forKey: .startFEN)
        if schemaVersion == 1,
           let legacyTags = try materializeLoadedTags() {
            try values.encode(
                GameTagCodec.encode(legacyTags),
                forKey: .loadedTags
            )
        } else {
            try values.encodeIfPresent(loadedTags, forKey: .loadedTags)
        }
        try values.encode(nodes, forKey: .nodes)
        try values.encodeIfPresent(currentNodeIndex, forKey: .currentNodeIndex)
    }

    /// Capture one live tree iteratively. Repeated node references are rejected:
    /// they would encode a graph whose single `parent` pointer cannot be restored
    /// truthfully as a tree.
    public init(
        capturing game: Game,
        maximumNodes: Int = PGNParser.maximumMoveTreeNodes
    ) throws {
        guard maximumNodes >= 0 else {
            throw GameTreeSnapshotError.invalidNodeLimit(maximumNodes)
        }

        var records: [Node] = []
        records.reserveCapacity(min(maximumNodes, game.rootChildren.count))
        var pending = game.rootChildren.reversed().map {
            (
                node: $0,
                parent: Optional<MoveNode>.none,
                parentIndex: Optional<Int>.none
            )
        }
        var seen = Set<ObjectIdentifier>()
        var capturedCurrentIndex: Int?

        while let item = pending.popLast() {
            guard records.count < maximumNodes else {
                throw GameTreeSnapshotError.nodeLimitExceeded(
                    maximumNodes: maximumNodes
                )
            }
            guard seen.insert(ObjectIdentifier(item.node)).inserted else {
                throw GameTreeSnapshotError.repeatedNodeReference
            }
            guard item.node.parent === item.parent else {
                throw GameTreeSnapshotError.inconsistentParentReference
            }

            let index = records.count
            if item.node === game.currentNode { capturedCurrentIndex = index }
            records.append(Node(
                parentIndex: item.parentIndex,
                moveUCI: item.node.move.uci,
                annotationRawValue: item.node.annotation?.rawValue,
                comment: item.node.comment,
                engineBestMoveUCI: item.node.engineBestMoveUCI,
                engineEval: item.node.engineEval,
                moveQualityRawValue: item.node.moveQuality?.rawValue,
                moveAccuracyBitPattern: item.node.moveAccuracy?.bitPattern,
                clockSecondsBitPattern: item.node.clockSeconds?.bitPattern
            ))
            pending.append(contentsOf: item.node.children.reversed().map {
                (
                    node: $0,
                    parent: Optional(item.node),
                    parentIndex: Optional(index)
                )
            })
        }

        if game.currentNode != nil, capturedCurrentIndex == nil {
            throw GameTreeSnapshotError.currentNodeNotInTree
        }
        let expectedPosition = game.currentNode?.positionAfter
            ?? game.startPosition
        guard game.position == expectedPosition else {
            throw GameTreeSnapshotError.inconsistentCurrentPosition
        }

        self.init(
            startFEN: game.startPosition.fen,
            loadedTags: game.loadedTags.map { tags in
                tags.insertionOrderedKeys.compactMap { key in
                    tags[key].map { Tag(key: key, value: $0) }
                }
            },
            nodes: records,
            currentNodeIndex: capturedCurrentIndex
        )
    }

    struct MaterializedTree {
        let startPosition: Position
        let roots: [MoveNode]
        let currentNode: MoveNode?
        let loadedTags: PGNGame.OrderedTags?
    }

    func materialize(
        maximumNodes: Int
    ) throws -> MaterializedTree {
        guard Self.supportsSchemaVersion(schemaVersion) else {
            throw GameTreeSnapshotError.unsupportedSchemaVersion(
                schemaVersion
            )
        }
        guard maximumNodes >= 0 else {
            throw GameTreeSnapshotError.invalidNodeLimit(maximumNodes)
        }
        guard nodes.count <= maximumNodes else {
            throw GameTreeSnapshotError.nodeLimitExceeded(
                maximumNodes: maximumNodes
            )
        }
        guard let start = Position(fen: startFEN) else {
            throw GameTreeSnapshotError.invalidStartFEN
        }
        if let currentNodeIndex,
           !nodes.indices.contains(currentNodeIndex) {
            throw GameTreeSnapshotError.invalidCurrentNodeIndex(
                currentNodeIndex
            )
        }
        let decodedLoadedTags = try materializeLoadedTags()

        var built: [MoveNode] = []
        built.reserveCapacity(nodes.count)
        var roots: [MoveNode] = []
        var siblingMoves: [Int: Set<String>] = [:]

        for (index, record) in nodes.enumerated() {
            let parent: MoveNode?
            let positionBefore: Position
            let siblingKey: Int
            if let parentIndex = record.parentIndex {
                guard parentIndex >= 0, parentIndex < index else {
                    throw GameTreeSnapshotError.invalidParentIndex(
                        nodeIndex: index,
                        parentIndex: parentIndex
                    )
                }
                parent = built[parentIndex]
                positionBefore = parent!.positionAfter
                siblingKey = parentIndex
            } else {
                parent = nil
                positionBefore = start
                siblingKey = -1
            }

            guard siblingMoves[siblingKey, default: []]
                .insert(record.moveUCI).inserted else {
                throw GameTreeSnapshotError.duplicateSiblingMove(
                    nodeIndex: index,
                    moveUCI: record.moveUCI
                )
            }
            let legalMoves = MoveGenerator.legalMoves(for: positionBefore)
            guard let move = UCIParser.uciToMove(
                record.moveUCI,
                in: legalMoves
            ) else {
                throw GameTreeSnapshotError.illegalMove(
                    nodeIndex: index,
                    moveUCI: record.moveUCI
                )
            }
            let annotation: MoveAnnotation?
            if let raw = record.annotationRawValue {
                guard let decoded = MoveAnnotation(rawValue: raw) else {
                    throw GameTreeSnapshotError.invalidAnnotation(
                        nodeIndex: index,
                        rawValue: raw
                    )
                }
                annotation = decoded
            } else {
                annotation = nil
            }
            let moveQuality: MoveQuality?
            if let raw = record.moveQualityRawValue {
                guard let decoded = MoveQuality(rawValue: raw) else {
                    throw GameTreeSnapshotError.invalidMoveQuality(
                        nodeIndex: index,
                        rawValue: raw
                    )
                }
                moveQuality = decoded
            } else {
                moveQuality = nil
            }

            let node = MoveNode(
                move: move,
                notation: MoveGenerator.algebraicNotation(
                    for: move,
                    in: positionBefore,
                    legalMoves: legalMoves
                ),
                positionBefore: positionBefore,
                parent: parent,
                plyIndex: (parent?.plyIndex ?? -1) + 1,
                annotation: annotation,
                comment: record.comment
            )
            node.engineBestMoveUCI = record.engineBestMoveUCI
            node.engineEval = record.engineEval
            node.moveQuality = moveQuality
            node.moveAccuracy = record.moveAccuracyBitPattern.map(
                Double.init(bitPattern:)
            )
            node.clockSeconds = record.clockSecondsBitPattern.map(
                Double.init(bitPattern:)
            )
            if let parent {
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            built.append(node)
        }

        return MaterializedTree(
            startPosition: start,
            roots: roots,
            currentNode: currentNodeIndex.map { built[$0] },
            loadedTags: decodedLoadedTags
        )
    }

    private func materializeLoadedTags() throws -> PGNGame.OrderedTags? {
        if let loadedTags {
            guard loadedTags.count <= Self.maximumLoadedTagPairs else {
                throw GameTreeSnapshotError.tagLimitExceeded(
                    maximumTags: Self.maximumLoadedTagPairs
                )
            }
            var tags = PGNGame.OrderedTags()
            var seen = Set<String>()
            for (index, tag) in loadedTags.enumerated() {
                guard !tag.key.isEmpty else {
                    throw GameTreeSnapshotError.emptyTagKey(index: index)
                }
                guard seen.insert(tag.key).inserted else {
                    throw GameTreeSnapshotError.duplicateTagKey(
                        index: index,
                        key: tag.key
                    )
                }
                tags[tag.key] = tag.value
            }
            return tags
        }
        return nil
    }
}

public nonisolated enum GameTreeSnapshotError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidNodeLimit(Int)
    case nodeLimitExceeded(maximumNodes: Int)
    case repeatedNodeReference
    case inconsistentParentReference
    case currentNodeNotInTree
    case inconsistentCurrentPosition
    case invalidStartFEN
    case invalidCurrentNodeIndex(Int)
    case invalidParentIndex(nodeIndex: Int, parentIndex: Int)
    case duplicateSiblingMove(nodeIndex: Int, moveUCI: String)
    case illegalMove(nodeIndex: Int, moveUCI: String)
    case invalidAnnotation(nodeIndex: Int, rawValue: String)
    case invalidMoveQuality(nodeIndex: Int, rawValue: String)
    case invalidLegacyTagEncoding
    case tagLimitExceeded(maximumTags: Int)
    case emptyTagKey(index: Int)
    case duplicateTagKey(index: Int, key: String)
}
