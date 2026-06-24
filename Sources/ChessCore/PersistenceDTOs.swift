import Foundation

// Plain Codable DTO mirrors of the app's SwiftData `@Model` persistence types.
//
// ChessCore can't reference SwiftData/`@Model`/CloudKit (Skip doesn't bridge
// them), so the portable logic (tactics/trap mining, repertoire auditing,
// stats) consumes these value types. The app converts `@Model` ↔ DTO at the
// boundary; Android persists the same DTOs via Room/files. (See also
// `PreparedGameData` in GameData.swift, the StoredGame mirror.)

// MARK: - Personal traps

/// Mirror of the `PersonalTrap` @Model — a "knife-edge" opening miss mined from
/// one of the user's games.
public struct PersonalTrapData: Sendable, Codable, Equatable {
    public var fen: String
    public var correctMoveUCI: String
    public var userActualMoveUCI: String
    public var gapCp: Int
    public var halfMoveIndex: Int
    public var sourceGameID: String
    public var sourceOpeningName: String
    public var detectedAt: Date

    public init(
        fen: String,
        correctMoveUCI: String,
        userActualMoveUCI: String,
        gapCp: Int,
        halfMoveIndex: Int,
        sourceGameID: String,
        sourceOpeningName: String,
        detectedAt: Date
    ) {
        self.fen = fen
        self.correctMoveUCI = correctMoveUCI
        self.userActualMoveUCI = userActualMoveUCI
        self.gapCp = gapCp
        self.halfMoveIndex = halfMoveIndex
        self.sourceGameID = sourceGameID
        self.sourceOpeningName = sourceOpeningName
        self.detectedAt = detectedAt
    }
}

/// Mirror of the `PersonalTrapScanRecord` @Model — per-game "already mined"
/// bookkeeping so the next scan pass can skip probed games.
public struct PersonalTrapScanRecordData: Sendable, Codable, Equatable {
    public var sourceGameID: String
    public var trapsFound: Int
    public var scannedAt: Date

    public init(sourceGameID: String, trapsFound: Int, scannedAt: Date) {
        self.sourceGameID = sourceGameID
        self.trapsFound = trapsFound
        self.scannedAt = scannedAt
    }
}

// MARK: - Game collections

/// Mirror of the `GameCollection` @Model metadata (the `games` relation and the
/// cached-annotated-count bookkeeping stay app-side with the @Model row).
public struct GameCollectionData: Sendable, Codable, Equatable {
    public var name: String
    public var source: String
    public var dateCreated: Date
    public var username: String
    public var lastSyncDate: Date?
    public var includeInOpeningBook: Bool
    public var orderIndex: Int

    public init(
        name: String,
        source: String = "pgn",
        dateCreated: Date = Date(timeIntervalSince1970: 0),
        username: String = "",
        lastSyncDate: Date? = nil,
        includeInOpeningBook: Bool = false,
        orderIndex: Int = 0
    ) {
        self.name = name
        self.source = source
        self.dateCreated = dateCreated
        self.username = username
        self.lastSyncDate = lastSyncDate
        self.includeInOpeningBook = includeInOpeningBook
        self.orderIndex = orderIndex
    }

    public var isOnlineCollection: Bool { source == "chesscom" || source == "lichess" }
}

// MARK: - Repertoire

/// Mirror of the `Repertoire` @Model, carrying its moves as a nested array (the
/// @Model uses a cascade relationship; the DTO flattens it to a value tree).
public struct RepertoireData: Sendable, Codable, Equatable {
    public var name: String
    public var color: String
    public var dateCreated: Date
    public var repertoireID: UUID?
    public var anchorFEN: String?
    public var anchorLineSAN: String?
    public var orderIndex: Int
    public var moves: [RepertoireMoveData]

    public init(
        name: String,
        color: String,
        dateCreated: Date = Date(timeIntervalSince1970: 0),
        repertoireID: UUID? = nil,
        anchorFEN: String? = nil,
        anchorLineSAN: String? = nil,
        orderIndex: Int = 0,
        moves: [RepertoireMoveData] = []
    ) {
        self.name = name
        self.color = color
        self.dateCreated = dateCreated
        self.repertoireID = repertoireID
        self.anchorFEN = anchorFEN
        self.anchorLineSAN = anchorLineSAN
        self.orderIndex = orderIndex
        self.moves = moves
    }

    /// Prefers the user-set `name`, falling back to a derived legacy label so
    /// pre-Phase-1 rows (empty `name`) read cleanly.
    public var displayName: String {
        name.isEmpty ? color.capitalized + " Repertoire" : name
    }
}

/// Mirror of the `RepertoireMove` @Model.
public struct RepertoireMoveData: Sendable, Codable, Equatable {
    public var positionKey: String
    public var san: String
    public var comment: String?
    public var auditDismissed: Bool

    public init(positionKey: String, san: String, comment: String? = nil, auditDismissed: Bool = false) {
        self.positionKey = positionKey
        self.san = san
        self.comment = comment
        self.auditDismissed = auditDismissed
    }
}

// MARK: - Fingerprinted JSON-blob caches

/// Shape of the per-key, fingerprinted JSON-blob cache rows the app keeps as
/// @Model tables (`CachedTacticsBundle`, `RepertoireAuditCache`,
/// `RepertoirePunishCache`): a key + corpus fingerprint + JSON payload + a
/// timestamp. The consumer compares `fingerprint` to the current corpus
/// fingerprint to decide reuse vs recompute.
public struct FingerprintedCacheData: Sendable, Codable, Equatable {
    public var key: String
    public var fingerprint: Int
    public var json: String
    public var updatedAt: Date

    public init(key: String, fingerprint: Int, json: String, updatedAt: Date) {
        self.key = key
        self.fingerprint = fingerprint
        self.json = json
        self.updatedAt = updatedAt
    }

    /// Whether a cache row may be reused: present and computed against the same
    /// corpus fingerprint.
    public func isValid(against currentFingerprint: Int) -> Bool {
        fingerprint == currentFingerprint
    }
}
