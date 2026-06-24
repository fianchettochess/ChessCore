// swift-tools-version: 6.0
//
// ChessCore — the portable, pure-Swift core carved out of the Fianchetto
// chess app so it can be shared by the Apple app AND the Android (Skip/SkipFuse)
// port. Foundation-only: NO SwiftData, CloudKit, GameKit, CoreML, UIKit, AppKit,
// SwiftUI, Combine, or CoreBluetooth — those stay app-side behind protocol seams.
//
// PRIVATE package (product IP). The extraction is dependency-ordered; see
// `docs/ANDROID_CARVE_PLAN.md` in the app repo for the full tranche plan. The
// intended internal boundary is PRIMITIVES (move generation, FEN, SAN<->UCI,
// PGN, opening book, UCI engine-output parsing — commodity, could one day be a
// thin public package) vs LOGIC (tactics, repertoire, trap mining, SRS,
// accuracy/Elo — differentiated). For now both live in one `ChessCore` target;
// they will be split into `ChessCorePrimitives` + `ChessCore` targets once the
// volume justifies it.
import PackageDescription

let package = Package(
    name: "ChessCore",
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
    targets: [
        .target(name: "ChessCore", path: "Sources/ChessCore"),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"], path: "Tests/ChessCoreTests"),
    ],
    // Swift 6 only. Carved files come from the app's Swift-5 target, so each is
    // made Swift 6-clean as it lands (e.g. DebouncedWriter's deinit became an
    // `isolated deinit` to satisfy strict concurrency).
    swiftLanguageModes: [.v6]
)
