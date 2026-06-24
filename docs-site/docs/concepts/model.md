# The Board Model

The foundational value types. All are `Sendable` and presentation-free —
colors, glyphs, and asset names are not part of the model and are left to the
consuming UI.

## PieceColor

```swift
public enum PieceColor: Equatable, Hashable, Codable, Sendable {
    case white, black
}
```

| Member | Meaning |
|---|---|
| `opposite` | the other side |
| `persistenceKey` | stable `"white"` / `"black"` storage key |
| `shortKey` | compact `"w"` / `"b"` |
| `init?(persistenceKey:)` | parse from the stable key |
| `static ofUser(white:black:username:)` | which side a username played (case-insensitive), or `nil` |

## PieceType

```swift
public enum PieceType: Equatable, Hashable, Codable, Sendable {
    case king, queen, rook, bishop, knight, pawn
}
```

A material-summary helper is available:

```swift
PieceType.materialSummary([.king: 1, .knight: 2, .pawn: 1])   // "K+2N+P"
```

## Piece

```swift
public struct Piece: Equatable, Hashable, Codable, Sendable {
    public let type: PieceType
    public let color: PieceColor
    public init(type: PieceType, color: PieceColor)
    public var fenChar: String        // uppercase for white, e.g. "N" / "n"
}
```

## Square

A board coordinate, file/rank `0...7`.

```swift
public struct Square: Hashable, Equatable, Codable, Sendable {
    public let file: Int
    public let rank: Int
    public init(file: Int, rank: Int)
    public init?(algebraic: String)   // "e4"
    public var isValid: Bool          // both in 0..<8
    public var fileChar: Character     // 'a'...'h'
    public var algebraic: String       // "e4"
    public var index: Int              // rank * 8 + file (0...63)
    public static func fromIndex(_ index: Int) -> Square
}
```

## CastlingRights

```swift
public struct CastlingRights: Equatable, Hashable, Codable, Sendable {
    public var whiteKingside  = true
    public var whiteQueenside = true
    public var blackKingside  = true
    public var blackQueenside = true
    public static let none: CastlingRights   // all false
}
```

## Move

A single move with full disambiguation metadata.

```swift
public struct Move: Equatable, Hashable, Sendable {
    public let from: Square
    public let to: Square
    public let piece: PieceType
    public let capturedPiece: PieceType?
    public let promotion: PieceType?
    public let isEnPassant: Bool
    public let isCastling: Bool

    public init(from: Square, to: Square, piece: PieceType,
                capturedPiece: PieceType? = nil, promotion: PieceType? = nil,
                isEnPassant: Bool = false, isCastling: Bool = false)

    public var uci: String   // "e2e4", "e7e8q"
}
```

## MoveRecord

A move paired with its SAN and the position it was played from:

```swift
public struct MoveRecord: Sendable {
    public let move: Move
    public let notation: String
    public let positionBefore: Position
}
```

## MoveAnnotation

The PGN/NAG glyphs. The chess logic only — display name, symbol, and tint are
left to the UI:

```swift
public enum MoveAnnotation: String, Equatable, Hashable, Sendable, CaseIterable {
    case brilliant = "!!", great, best, excellent
    case good = "!", interesting = "!?", dubious = "?!"
    case miss, mistake = "?", blunder = "??"
}
```

```swift
let (cleaned, annotation) = MoveAnnotation.extract(from: "Nf3!?")  // ("Nf3", .interesting)
let fromNag = MoveAnnotation.from(nag: 1)                          // .good
let suffix  = MoveAnnotation.brilliant.pgnSuffix                   // the PGN suffix
```

## MoveQuality

Engine move-quality classification (display is left to the UI):

```swift
public enum MoveQuality: String, CaseIterable, Sendable {
    case best, excellent, good, inaccuracy, mistake, blunder
}
```

## GameState

```swift
public enum GameState: Equatable, Sendable {
    case playing, check, checkmate, stalemate
    case draw, insufficientMaterial, repetition
    public var isGameOver: Bool
}
```

## Position

The complete board state, plus FEN parse/serialize and material/EP analysis.

```swift
public struct Position: Equatable, Sendable {
    public var board: [Piece?]              // 64 entries
    public var activeColor: PieceColor
    public var castlingRights: CastlingRights
    public var enPassantTarget: Square?
    public var halfmoveClock: Int
    public var fullmoveNumber: Int
    public var whiteKingSquare: Square
    public var blackKingSquare: Square

    public init()                            // empty board, White to move
    public init?(fen: String)                // standard FEN (failable)
    public subscript(square: Square) -> Piece? { get set }  // bounds-safe

    public static func initial() -> Position // standard start

    public var fen: String                   // full FEN incl. counters
    public var positionKey: String           // FEN without counters (the cache/legality key)
    public var stockfishSafeFEN: String      // sanitized for a strict UCI engine
    public var capturableEnPassantTarget: Square?  // EP only when a capture exists
    public var hasInsufficientMaterial: Bool
}
```

See [FEN](fen.md) for the three FEN-shaped accessors and when to use each.
