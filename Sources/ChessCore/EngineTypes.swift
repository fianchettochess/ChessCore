import Foundation

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
        /// Stable identity across engine publishes: a fresh UUID per
        /// publish made every list row "new" on each 10Hz analysis
        /// update, forcing full row diff/animation churn. SAN notation
        /// is unique within one position's move list and stable across
        /// depth updates for the same move.
        /// (perf/battery sweep 2026-06-11 #8b)
        public var id: String { notation }
        public let move: Move
        public let notation: String
        public let probability: Double
        public let score: UCIInfo.Score?
        public let pvLine: [String]

        public init(move: Move, notation: String, probability: Double, score: UCIInfo.Score? = nil, pvLine: [String] = []) {
            self.move = move
            self.notation = notation
            self.probability = probability
            self.score = score
            self.pvLine = pvLine
        }
    }

    public enum Evaluation: Equatable, Sendable {
        case winDrawLoss(win: Double, draw: Double, loss: Double)
        case centipawns(Int)
        case mate(Int)

        public var displayText: String {
            switch self {
            case .winDrawLoss(let w, let d, let l):
                return String(format: "W %.0f%% D %.0f%% L %.0f%%", w * 100, d * 100, l * 100)
            case .centipawns(let cp):
                return String(format: "%+.2f", Double(cp) / 100.0)
            case .mate(let m):
                return "M\(abs(m))"
            }
        }

        public var scoreText: String {
            switch self {
            case .centipawns(let cp):
                return String(format: "%+.1f", Double(cp) / 100.0)
            case .mate(let m):
                return "M\(abs(m))"
            case .winDrawLoss(let w, _, let l):
                let diff = w - l
                return String(format: "%+.0f%%", diff * 100)
            }
        }
    }
}

public enum EngineError: LocalizedError {
    case modelNotLoaded
    case invalidInput
    case predictionFailed(String)
    case noLegalMoves

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "No engine loaded"
        case .invalidInput: "Failed to encode position"
        case .predictionFailed(let msg): "Prediction failed: \(msg)"
        case .noLegalMoves: "No legal moves in position"
        }
    }
}
