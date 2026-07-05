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
    // Generous community floor: iOS 13 / macOS 10.15 (the Swift-concurrency
    // back-deployment line; SwiftStockfish parity). The code is pure Swift
    // stdlib + Foundation and has been verified to build down to iOS 11 / macOS
    // 10.10; it can be lowered to iOS 12 / macOS 10.13 (Swift-ABI-stable line)
    // for maximum reach at zero API cost if a public release wants it.
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
    // DocC generation only — the swift-docc-plugin is a build-tool/command plugin
    // and adds NOTHING to the library's own dependency graph or its compiled
    // output. Consumers of ChessCore never see it.
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .target(name: "ChessCore", path: "Sources/ChessCore"),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"], path: "Tests/ChessCoreTests"),
    ],
    // Swift 6 only. Carved files come from the app's Swift-5 target, so each is
    // made Swift 6-clean as it lands (e.g. DebouncedWriter's deinit became an
    // `isolated deinit` to satisfy strict concurrency).
    swiftLanguageModes: [.v6]
)
