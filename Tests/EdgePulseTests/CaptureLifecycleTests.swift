import XCTest
@testable import EdgePulse

final class CaptureLifecycleTests: XCTestCase {
    func testStopInvalidatesInFlightStart() {
        var lifecycle = CaptureLifecycle()
        let token = try! XCTUnwrap(lifecycle.requestStart())

        lifecycle.requestStop()

        XCTAssertFalse(lifecycle.accepts(token))
        XCTAssertFalse(lifecycle.didStart(token: token))
        XCTAssertEqual(lifecycle.phase, .idle)
        XCTAssertFalse(lifecycle.wantsCapture)
    }

    func testDuplicateStartIsIdempotent() {
        var lifecycle = CaptureLifecycle()

        XCTAssertNotNil(lifecycle.requestStart())
        XCTAssertNil(lifecycle.requestStart())
        XCTAssertEqual(lifecycle.phase, .starting)
    }

    func testRapidTogglesOnlyAcceptNewestGeneration() {
        var lifecycle = CaptureLifecycle()
        var staleTokens: [UInt64] = []

        for _ in 0..<100 {
            staleTokens.append(try! XCTUnwrap(lifecycle.requestStart()))
            lifecycle.requestStop()
        }

        let newestToken = try! XCTUnwrap(lifecycle.requestStart())
        XCTAssertTrue(staleTokens.allSatisfy { !lifecycle.accepts($0) })
        XCTAssertTrue(lifecycle.didStart(token: newestToken))
        XCTAssertEqual(lifecycle.phase, .running)
    }

    func testPermissionDenialAllowsLaterRetry() {
        var lifecycle = CaptureLifecycle()
        let firstToken = try! XCTUnwrap(lifecycle.requestStart())

        XCTAssertTrue(lifecycle.permissionWasDenied(token: firstToken))
        XCTAssertEqual(lifecycle.phase, .permissionRequired)
        XCTAssertFalse(lifecycle.wantsCapture)

        let retryToken = try! XCTUnwrap(lifecycle.requestStart())
        XCTAssertGreaterThan(retryToken, firstToken)
        XCTAssertTrue(lifecycle.didStart(token: retryToken))
    }

    func testStaleStreamStopCannotFailNewSession() {
        var lifecycle = CaptureLifecycle()
        let oldToken = try! XCTUnwrap(lifecycle.requestStart())
        lifecycle.requestStop()
        let newToken = try! XCTUnwrap(lifecycle.requestStart())
        XCTAssertTrue(lifecycle.didStart(token: newToken))

        XCTAssertFalse(lifecycle.activeStreamStopped(token: oldToken))
        XCTAssertEqual(lifecycle.phase, .running)
        XCTAssertTrue(lifecycle.wantsCapture)
    }
}
