// swift-tools-version: 6.0
//
// ChessCore — a general-purpose, MIT-licensed chess core, carved out of the
// Fianchetto app so it can be shared by the Apple app, the Android (Skip/
// SkipFuse) port, and the wider Swift chess community.
//
// Scope: the position model, move generation (+ perft), FEN, SAN<->UCI
// conversion, PGN read/write, and the UCI engine-probe protocol. Foundation-only
// and NETWORK-FREE — NO SwiftData, CloudKit, GameKit, CoreML, UIKit, AppKit,
// SwiftUI, Combine, CoreBluetooth, or URLSession. App-specific product logic and
// network service clients live in separate downstream packages.
import PackageDescription

let package = Package(
    name: "ChessCore",
    // Lowest viable floor: iOS 13 / macOS 10.15 — the Swift-concurrency
    // back-deployment line (SwiftStockfish/SwiftReckless parity). This is a hard
    // floor: the public API includes async engine seams — `ChessEngine.analyze`
    // (async), `UCIEngine.output` (AsyncStream), and two internal actors — which
    // the concurrency runtime supports only down to iOS 13 / macOS 10.15. The
    // pure value types (model, move generation, FEN, SAN<->UCI, PGN) would build
    // lower on their own, but cannot be declared lower while those async seams
    // stay in this module (they'd fail on iOS 12). To go lower, the engine
    // protocols would have to move to a separate downstream package.
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "ChessCore", targets: ["ChessCore"]),
    ],
    // The command plugin provides `swift package generate-documentation`. It is
    // resolved and downloaded with the package, but is not linked into the
    // ChessCore library product.
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .target(name: "ChessCore", path: "Sources/ChessCore"),
        // Release-only micro-benchmarks. Invisible to library consumers (they
        // depend on the `ChessCore` library product) and never pulled into the
        // Skip/Android transpile. Run: `swift run -c release ChessCoreBench`.
        .executableTarget(name: "ChessCoreBench", dependencies: ["ChessCore"], path: "Sources/ChessCoreBench"),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"], path: "Tests/ChessCoreTests"),
    ],
    // Compile public sources in Swift 6 language mode with strict concurrency.
    swiftLanguageModes: [.v6]
)
