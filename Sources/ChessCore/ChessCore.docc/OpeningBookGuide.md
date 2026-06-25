# Opening Book

Map a position to its ECO code and opening name, list book continuations, and
share one process-wide instance — all with transposition-aware en-passant
normalization.

## Overview

``OpeningBook`` is data-driven: you supply precomputed opening data, then look up
a position (or a SAN move list) to get an ``OpeningBook/Entry``, or ask for the
``OpeningBook/BookMove`` continuations from a position.

## Construction

You supply precomputed opening data as JSON or a property list (for example a
bundled `openings_precomputed.json` / `.plist`).

```swift
let data = try Data(contentsOf: bundledOpeningsURL)
let book = OpeningBook(precomputedData: data, isPlist: false)   // failable
```

``OpeningBook/init(precomputedData:isPlist:)`` returns `nil` if the data can't be
decoded. ``OpeningBook/init()`` builds an empty book.

## Shared instance

For application-wide use, install a process-wide instance once with
``OpeningBook/configureShared(precomputedData:isPlist:)`` and read it anywhere
through ``OpeningBook/shared``:

```swift
// At startup:
OpeningBook.configureShared(precomputedData: data, isPlist: false)

// Anywhere:
if let entry = OpeningBook.shared.lookup(position) {
    print(entry.eco, entry.name)
}
```

> Note: ``OpeningBook/shared`` is empty until
> ``OpeningBook/configureShared(precomputedData:isPlist:)`` is called.

## Lookup

An ``OpeningBook/Entry`` carries the ECO code, the opening name, and whether the
entry is terminal:

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
a direct hit. See <doc:FENs> for how ``Position/capturableEnPassantTarget``
defines a "real" en-passant target.

## Continuations

An ``OpeningBook/BookMove`` is a book continuation: its SAN, plus the resolved
opening name and ECO of the position it reaches.

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

The book exposes the key helpers it uses, so you can build your own
transposition table on the same canonical form:

```swift
OpeningBook.positionKey(position)              // FEN's first 4 fields
OpeningBook.epNormalizedKey(position)          // EP reduced to a *capturable* square (or "-")
OpeningBook.epNormalizedKey(forStoredKey: key) // canonicalize a stored key string
```

``OpeningBook/positionKey(_:)`` is the raw four-field key;
``OpeningBook/epNormalizedKey(_:)`` equals it unless the position holds a phantom
EP target. The stored-key variant
``OpeningBook/epNormalizedKey(forStoredKey:)`` is idempotent and skips the FEN
parse for the common "no EP" case.

## See Also

- <doc:FENs>
- <doc:ConvertingMoveNotation>
- ``OpeningBook``
