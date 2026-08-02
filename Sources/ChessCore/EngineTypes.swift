import Foundation

/// A source of analysis for a position.
///
/// The seam is deliberately small: hand it a `Position`, get back an
/// `EngineAnalysis`. A UCI process wrapper, a neural policy network, an
/// endgame-tablebase client, and a fixed opening book can all satisfy it.
///
/// - Important: `ChessEngine` is a class protocol and is intentionally **not**
///   `Sendable` — the ordinary implementation is a class with mutable search
///   state, and requiring `Sendable` would outlaw it. Confine an engine
///   instance to one isolation domain (an actor, or the main actor) and call
///   `analyze` from there. `Position` and `EngineAnalysis` are both `Sendable`,
///   so the values crossing the seam are safe to move between domains even
///   though the engine itself is not.
public protocol ChessEngine: AnyObject {
    var name: String { get }
    var isReady: Bool { get }
    func analyze(position: Position, topK: Int) async throws -> EngineAnalysis
}

public struct EngineAnalysis: Sendable {
    public let topMoves: [ScoredMove]
    public let evaluation: Evaluation?
    public let depth: Int?

    public init(topMoves: [ScoredMove], evaluation: Evaluation?, depth: Int? = nil) {
        self.topMoves = topMoves
        self.evaluation = evaluation
        self.depth = depth
    }

    public struct ScoredMove: Identifiable, Sendable {
        /// SAN notation, which is unique within one position's move list and
        /// stable across depth updates for the same move.
        ///
        /// Identity is deliberately derived rather than generated: a fresh
        /// `UUID` per publish would make every row of a live analysis list
        /// "new" on each update, forcing a full diff on every engine tick.
        public var id: String { notation }
        public let move: Move
        public let notation: String
        /// Likelihood this move is played, in `0...1`, when the engine is a
        /// policy network that produces one.
        ///
        /// `nil` for search engines. A UCI engine ranks by evaluation and has
        /// no probability to report, so it leaves this unset rather than
        /// inventing a value that would be indistinguishable from a genuine
        /// zero. Rank by `score` when this is `nil`.
        public let probability: Double?
        public let score: UCIInfo.Score?
        public let pvLine: [String]

        public init(
            move: Move,
            notation: String,
            probability: Double? = nil,
            score: UCIInfo.Score? = nil,
            pvLine: [String] = []
        ) {
            self.move = move
            self.notation = notation
            self.probability = probability
            self.score = score
            self.pvLine = pvLine
        }
    }

    /// An engine's assessment of a position, in whichever form the engine
    /// natively produces. Formatting it for a reader is the caller's job.
    public enum Evaluation: Equatable, Sendable {
        case winDrawLoss(win: Double, draw: Double, loss: Double)
        case centipawns(Int)
        case mate(Int)
    }
}

public enum EngineError: LocalizedError {
    /// No engine is loaded, or the loaded engine is not ready to analyze.
    case engineUnavailable
    /// The position could not be encoded into the engine's input format.
    case invalidPosition
    /// The engine ran but produced no usable result.
    case analysisFailed(String)
    /// The position has no legal moves, so there is nothing to rank.
    case noLegalMoves

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable: "No engine loaded"
        case .invalidPosition: "Failed to encode position"
        case .analysisFailed(let msg): "Analysis failed: \(msg)"
        case .noLegalMoves: "No legal moves in position"
        }
    }
}
