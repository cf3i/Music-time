import XCTest
@testable import EdgePulse

final class OverlayPlacementTests: XCTestCase {
    func testEveryPlacementMapsToExpectedPhysicalEdges() {
        XCTAssertEqual(EdgePlacement.bottom.overlayEdges, [.bottom])
        XCTAssertEqual(EdgePlacement.top.overlayEdges, [.top])
        XCTAssertEqual(EdgePlacement.left.overlayEdges, [.left])
        XCTAssertEqual(EdgePlacement.right.overlayEdges, [.right])
        XCTAssertEqual(EdgePlacement.all.overlayEdges, [.bottom, .top, .left, .right])
    }

    func testHorizontalAndVerticalEdgesReportOrientation() {
        XCTAssertTrue(OverlayEdge.bottom.isHorizontal)
        XCTAssertTrue(OverlayEdge.top.isHorizontal)
        XCTAssertFalse(OverlayEdge.left.isHorizontal)
        XCTAssertFalse(OverlayEdge.right.isHorizontal)
    }
}
