import XCTest
@testable import ChessCore

final class ChessModelTests: XCTestCase {
    func testInitialPositionFEN() {
        XCTAssertEqual(
            Position.initial().fen,
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        )
    }

    func testFENRoundTrip() {
        let fen = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 2 3"
        let pos = Position(fen: fen)
        XCTAssertNotNil(pos)
        XCTAssertEqual(pos?.fen, fen)
        XCTAssertEqual(pos?.activeColor, .black)
        XCTAssertEqual(pos?[Square(algebraic: "c6")!], Piece(type: .knight, color: .black))
    }

    func testInvalidFENRejected() {
        XCTAssertNil(Position(fen: "not a fen"))
        XCTAssertNil(Position(fen: "rnbqkbnr/pppppppp/8/8/8 w KQkq - 0 1")) // too few ranks
    }

    func testInsufficientMaterial() {
        // K vs K
        var kvk = Position()
        kvk[Square(file: 4, rank: 0)] = Piece(type: .king, color: .white)
        kvk[Square(file: 4, rank: 7)] = Piece(type: .king, color: .black)
        XCTAssertTrue(kvk.hasInsufficientMaterial)
        // K+pawn vs K is sufficient
        var withPawn = kvk
        withPawn[Square(file: 0, rank: 1)] = Piece(type: .pawn, color: .white)
        XCTAssertFalse(withPawn.hasInsufficientMaterial)
    }

    func testSquareAndMoveEncoding() {
        XCTAssertEqual(Square(file: 4, rank: 1).algebraic, "e2")
        XCTAssertEqual(Square(algebraic: "e2"), Square(file: 4, rank: 1))
        XCTAssertNil(Square(algebraic: "z9"))
        let promo = Move(from: Square(algebraic: "e7")!, to: Square(algebraic: "e8")!, piece: .pawn, promotion: .queen)
        XCTAssertEqual(promo.uci, "e7e8q")
    }

    func testPieceColorKeys() {
        XCTAssertEqual(PieceColor.white.opposite, .black)
        XCTAssertEqual(PieceColor.black.persistenceKey, "black")
        XCTAssertEqual(PieceColor(persistenceKey: "white"), .white)
        XCTAssertNil(PieceColor(persistenceKey: "grey"))
        XCTAssertEqual(PieceColor.ofUser(white: "Magnus", black: "Hikaru", username: "hikaru"), .black)
    }

    func testMoveAnnotationParsing() {
        XCTAssertEqual(MoveAnnotation.from(nag: 4), .blunder)
        let (cleaned, annotation) = MoveAnnotation.extract(from: "Qxf7??")
        XCTAssertEqual(cleaned, "Qxf7")
        XCTAssertEqual(annotation, .blunder)
        XCTAssertEqual(MoveAnnotation.blunder.pgnSuffix, "??")
        XCTAssertNil(MoveAnnotation.best.pgnSuffix)
    }
}
