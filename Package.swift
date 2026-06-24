// swift-tools-version: 6.0
//
// Two products carved out of the Fianchetto chess app so they can be shared by
// the Apple app AND the Android (Skip/SkipFuse) port:
//
//   • ChessCore — the GENERAL, community-grade chess core: the position model,
//     move generation (+ perft), FEN, SAN<->UCI, PGN, opening book, the engine
//     probe protocol, general analysis math, and the storage seam protocols.
//     Foundation-only, NO SwiftData/CloudKit/GameKit/CoreML/UIKit/AppKit/SwiftUI/
//     Combine/CoreBluetooth. Intended for an eventual permissive public release;
//     the stale ChessKit incumbents leave this niche underserved.
//
//   • FianchettoKit — Fianchetto's DIFFERENTIATED product logic (private):
//     tactics-from-your-games, repertoire build/audit/punish, personal trap
//     mining, the SRS/stat stores, the @Model DTO mirrors. Depends on ChessCore.
//
// The dependency direction is one-way (FianchettoKit -> ChessCore); ChessCore
// never references the app logic. See `docs/ANDROID_CARVE_PLAN.md`.
import PackageDescription

let package = Package(
    name: "ChessCore",
    // Declared floor: iOS 13 / macOS 10.15 (parity with SwiftStockfish; the
    // Swift-concurrency back-deployment line). ChessCore's code is pure Swift
    // stdlib + Foundation and has been verified to build down to iOS 11 / macOS
    // 10.10 (the toolchain minimum). NOTE: this package-level floor applies to
    // BOTH targets; to give FianchettoKit its own (higher, Fianchetto-matching)
    // floor it would need to be a separate package — see the package header.
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "ChessCore", targets: ["ChessCore"]),
        .library(name: "FianchettoKit", targets: ["FianchettoKit"]),
    ],
    targets: [
        .target(name: "ChessCore", path: "Sources/ChessCore"),
        .target(name: "FianchettoKit", dependencies: ["ChessCore"], path: "Sources/FianchettoKit"),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"], path: "Tests/ChessCoreTests"),
        .testTarget(name: "FianchettoKitTests", dependencies: ["FianchettoKit"], path: "Tests/FianchettoKitTests"),
    ],
    // Swift 6 only. Carved files come from the app's Swift-5 target, so each is
    // made Swift 6-clean as it lands (e.g. DebouncedWriter's deinit became an
    // `isolated deinit` to satisfy strict concurrency).
    swiftLanguageModes: [.v6]
)
