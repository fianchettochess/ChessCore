# Storage Seam

The persistence portability seam: write rating, SRS, and history logic once
against two small protocols, and run it on any backend.

## Overview

A store's *logic* depends only on two small protocols — ``JSONBlobStore`` (the
key → JSON-string backend you supply) and ``BlobBackedStore`` (a `Codable` value
persisted as one blob) — while the concrete backend (a database, files, the
cloud, or an in-memory map) is supplied by the caller. This is what lets rating,
SRS, and history logic be written once and run against any storage.

## JSONBlobStore: the backend

You implement ``JSONBlobStore`` over whatever persistence you have. It is a
key → JSON-string blob store:

```swift
public protocol JSONBlobStore {
    func loadJSON(forKey key: String) -> String?
    func saveJSON(_ json: String, forKey key: String)
}
```

- ``JSONBlobStore/loadJSON(forKey:)`` returns the current JSON payload, or `nil`
  if absent / unreadable.
- ``JSONBlobStore/saveJSON(_:forKey:)`` persists `json`. It may be asynchronous
  or debounced internally; callers treat it as fire-and-forget.

The simplest possible backend:

```swift
import ChessCore

final class MemoryBlobStore: JSONBlobStore {
    private var storage: [String: String] = [:]
    func loadJSON(forKey key: String) -> String? { storage[key] }
    func saveJSON(_ json: String, forKey key: String) { storage[key] = json }
}
```

A real Apple backend backs ``JSONBlobStore/saveJSON(_:forKey:)`` with a debounced
write into a SwiftData row that CloudKit mirrors; an Android backend writes a
Room row. The store logic never changes.

## BlobBackedStore: a single-row Codable store

A ``BlobBackedStore`` is a `Codable` value persisted as one JSON blob under a
stable key:

```swift
public protocol BlobBackedStore: Codable {
    static var blobKey: String { get }
    init()
}
```

The protocol extension provides `load` / `save` for free:

```swift
public extension BlobBackedStore {
    static func load(from store: JSONBlobStore, decoder: JSONDecoder = JSONDecoder()) -> Self
    func save(to store: JSONBlobStore, encoder: JSONEncoder = JSONEncoder())
}
```

`load(from:)` decodes from `store[blobKey]` and **falls back to a fresh
`Self()`** when the blob is missing or malformed, so a first run and a corrupt
row both just start clean. `save(to:)` encodes and persists, silently dropping on
an encode failure.

> Note: Because `load(from:)` always returns a value — falling back to `Self()`
> on a missing or malformed blob — a ``BlobBackedStore`` never throws on read. A
> corrupt row is indistinguishable from a first launch.

## Defining your own store

```swift
import ChessCore

struct Settings: BlobBackedStore {
    static let blobKey = "settings"
    var theme = "system"
    var boardFlipped = false
    init() {}
}

let blobStore = MemoryBlobStore()

var settings = Settings.load(from: blobStore)   // decodes blobStore["settings"]
settings.boardFlipped = true
settings.save(to: blobStore)                    // encodes it back
```

This is exactly the pattern Fianchetto's stat stores use — their tactics-rating,
tactics-performance, and repertoire-drill stores are all ``BlobBackedStore``
conformers, so the same Elo and SRS math runs on every backend.

## See Also

- <doc:AnalysisMath>
- ``JSONBlobStore``
- ``BlobBackedStore``
