# Installation

ChessCore is a Swift Package Manager library with no third-party runtime
dependencies — only Foundation.

## Requirements

| | Minimum |
|---|---|
| Swift tools | 6.0 (Swift 6 language mode) |
| iOS | 13.0 |
| macOS | 10.15 |
| tvOS | 13.0 |
| watchOS | 6.0 |
| visionOS | 1.0 |

The floor is a hard one set by the async engine seams (`ChessEngine.analyze`,
`UCIEngine.output`) and Swift-concurrency back-deployment; the pure value types
would build lower on their own, but the package cannot declare a lower target
while those seams live in this module.

## Add the package

### Remote dependency

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/fianchettochess/ChessCore.git", .upToNextMinor(from: "0.9.0")),
],
targets: [
    .target(
        name: "MyChessApp",
        dependencies: [
            .product(name: "ChessCore", package: "ChessCore"),
        ]
    ),
]
```

### Choosing a version requirement

ChessCore is pre-1.0, and under `0.x` the minor is the breaking position: a
`0.8.0 → 0.9.0` step may break source compatibility, a `0.7.1 → 0.7.2` step will
not. The changelog records what changed in each.

Prefer `.upToNextMinor(from:)` over `from:`. SwiftPM does not special-case `0.x`
the way some other package managers do — `from: "0.9.0"` is shorthand for
`.upToNextMajor(from: "0.9.0")`, which resolves `0.9.0 ..< 1.0.0` and would
accept a breaking `0.10.0`.

### Local path dependency

For a local checkout located alongside your project, use a path dependency:

```swift
dependencies: [
    .package(path: "../ChessCore"),
],
```

### Xcode

In Xcode: **File ▸ Add Package Dependencies…**, enter the repository URL (or add
the local package), and add the **ChessCore** library product to your target.

## Import

```swift
import ChessCore
```

## Building the API documentation

ChessCore ships a DocC catalog and declares the
[swift-docc-plugin](https://github.com/swiftlang/swift-docc-plugin), which adds
the documentation command below. SwiftPM resolves the plugin package, but it is
not linked into the ChessCore library product.

```bash
swift package generate-documentation --target ChessCore
# or, to a directory you choose:
swift package --allow-writing-to-directory ./docs \
    generate-documentation --target ChessCore --output-path ./docs
```

## Verifying the install

```bash
swift build
swift test          # runs the perft suite and the parser/notation tests
```
