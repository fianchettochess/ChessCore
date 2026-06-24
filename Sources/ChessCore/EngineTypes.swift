import Foundation

public protocol ChessEngine: AnyObject {
    var name: String { get }
    var isReady: Bool { get }
    func analyze(position: Position, topK: Int) async throws -> EngineAnalysis
}

public struct EngineAnalysis {
    public let topMoves: [ScoredMove]
    public let evaluation: Evaluation?
    public let depth: Int?

    public init(topMoves: [ScoredMove], evaluation: Evaluation?, depth: Int? = nil) {
        self.topMoves = topMoves
        self.evaluation = evaluation
        self.depth = depth
    }

    public struct ScoredMove: Identifiable {
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
        public let score: StockfishInfo.Score?
        public let pvLine: [String]

        public init(move: Move, notation: String, probability: Double, score: StockfishInfo.Score? = nil, pvLine: [String] = []) {
            self.move = move
            self.notation = notation
            self.probability = probability
            self.score = score
            self.pvLine = pvLine
        }
    }

    public enum Evaluation: Equatable {
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

        public var whiteWinProbability: Double {
            switch self {
            case .winDrawLoss(let w, _, let l):
                let total = w + l
                return total > 0 ? w / total : 0.5
            case .centipawns(let cp):
                return 1.0 / (1.0 + exp(-0.00368208 * Double(cp)))
            case .mate(let m):
                return m > 0 ? 1.0 : 0.0
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

public struct GameAnalysis {
    public struct MoveResult {
        public let moveIndex: Int
        public let playerMoveRank: Int
        public let playerMoveProbability: Double

        public init(moveIndex: Int, playerMoveRank: Int, playerMoveProbability: Double) {
            self.moveIndex = moveIndex
            self.playerMoveRank = playerMoveRank
            self.playerMoveProbability = playerMoveProbability
        }
    }

    public let moveResults: [MoveResult]

    public init(moveResults: [MoveResult]) {
        self.moveResults = moveResults
    }

    public var accuracy: Double {
        guard !moveResults.isEmpty else { return 0 }
        return Double(moveResults.filter { $0.playerMoveRank == 0 }.count) / Double(moveResults.count)
    }

    public var top3Accuracy: Double {
        guard !moveResults.isEmpty else { return 0 }
        return Double(moveResults.filter { (0..<3).contains($0.playerMoveRank) }.count) / Double(moveResults.count)
    }

    public var averageProbability: Double {
        guard !moveResults.isEmpty else { return 0 }
        return moveResults.map(\.playerMoveProbability).reduce(0, +) / Double(moveResults.count)
    }
}

public struct GuessEloResult {
    public let whiteElo: Int?
    public let blackElo: Int?

    public init(whiteElo: Int?, blackElo: Int?) {
        self.whiteElo = whiteElo
        self.blackElo = blackElo
    }
}

public struct PositionEval {
    public let bestMoveUCI: String
    public let scores: [Int: StockfishInfo.Score]

    public init(bestMoveUCI: String, scores: [Int: StockfishInfo.Score]) {
        self.bestMoveUCI = bestMoveUCI
        self.scores = scores
    }

    public var bestScore: StockfishInfo.Score {
        scores[1] ?? .cp(0)
    }

    public var secondBestScore: StockfishInfo.Score? {
        scores[2]
    }
}

public struct PlayConfig: Equatable {
    public enum Engine: String, CaseIterable {
        case maia = "Maia"
        case stockfish = "Stockfish"
    }
    public enum PlayerColor: String, CaseIterable {
        case white = "White"
        case black = "Black"
    }
    public var engine: Engine
    public var playerColor: PlayerColor

    public init(engine: Engine, playerColor: PlayerColor) {
        self.engine = engine
        self.playerColor = playerColor
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
