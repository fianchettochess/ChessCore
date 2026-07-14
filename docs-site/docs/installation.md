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

The floor is set by Swift-concurrency back-deployment; the code itself is pure
Swift stdlib + Foundation and builds down to iOS 11 / macOS 10.10.

## Add the package

### Remote dependency

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/fianchettochess/ChessCore", from: "0.1.0"),
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

ChessCore ships a DocC catalog and depends on the
[swift-docc-plugin](https://github.com/swiftlang/swift-docc-plugin) for
generation:

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
