# Opening Book

`OpeningBook` maps a position to its ECO code / opening name and lists book
continuations, with a process-wide shared instance and transposition-aware
en-passant normalization.

## Construction

The book is data-driven: you supply precomputed opening data as JSON or a
property list (for example a bundled `openings_precomputed.json` / `.plist`).

```swift
let data = try Data(contentsOf: bundledOpeningsURL)
let book = OpeningBook(precomputedData: data, isPlist: false)   // failable
```

`init(precomputedData:isPlist:)` returns `nil` if the data can't be decoded.
`OpeningBook()` builds an empty book.

## The shared book

For app-wide use, install a process-wide instance once and read it anywhere:

```swift
// At startup:
OpeningBook.configureShared(precomputedData: data, isPlist: false)

// Anywhere:
if let entry = OpeningBook.shared.lookup(position) {
    print(entry.eco, entry.name)
}
```

`OpeningBook.shared` is empty until `configureShared` is called.

## Lookup

```swift
public struct Entry: Sendable {
    public let eco: String
    public let name: String
    public let isTerminal: Bool
}
```

```swift
// By position:
let entry = book.lookup(position)                 // Entry?

// By a SAN move list (replayed from the start):
let entry2 = book.lookup(["e4", "e5", "Nf3", "Nc6", "Bb5"])

// ECO -> name:
let name = book.openingName(forECO: "C60")

// Reverse: find a position that reaches a named opening:
let pos = book.findPosition(forOpening: "Ruy Lopez")   // exact, then prefix, then contains
```

Lookup is transposition-aware: when a position's en-passant target isn't actually
capturable, the book retries with the EP square dropped — but it never overrides
a direct hit.

## Continuations

```swift
public struct BookMove: Sendable {
    public let san: String
    public let openingName: String?
    public let eco: String?
}
```

```swift
let moves = book.continuations(for: position)        // [BookMove]
let moves2 = book.continuations(after: ["e4", "e5"]) // after a SAN line

for m in moves {
    print(m.san, m.openingName ?? "", m.eco ?? "")
}
```

Continuations are cached, and each one's resulting opening name / ECO is
resolved.

## Position keys

The book exposes the key helpers it uses, in case you want to build your own
transposition table on the same canonical form:

```swift
OpeningBook.positionKey(position)              // FEN's first 4 fields
OpeningBook.epNormalizedKey(position)          // EP reduced to a *capturable* square (or "-")
OpeningBook.epNormalizedKey(forStoredKey: key) // canonicalize a stored key string
```

`epNormalizedKey` equals `positionKey` unless the position holds a phantom EP
target; the stored-key variant is idempotent and skips the FEN parse for the
common "no EP" case.
