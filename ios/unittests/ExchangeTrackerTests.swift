import XCTest
@testable import Coin

/// Synthetic MediaPipe frames: shoulders 0.2 apart at y = 0.35, hips at y = 0.6, orthodox stance (lead = left = index 15).
private struct Body {
    var hipX = 0.5
    var lead = (0.45, 0.30)     // guard: wrists near the face, above the shoulder line
    var rear = (0.55, 0.30)

    func joints() -> [PoseJoint] {
        var j = Array(repeating: PoseJoint(x: 0.5, y: 0.5, visibility: 0.0), count: 33)
        func set(_ i: Int, _ x: Double, _ y: Double) { j[i] = PoseJoint(x: x, y: y, visibility: 0.95) }
        set(11, hipX - 0.1, 0.35); set(12, hipX + 0.1, 0.35)
        set(15, lead.0 + hipX - 0.5, lead.1); set(16, rear.0 + hipX - 0.5, rear.1)
        set(23, hipX - 0.08, 0.6); set(24, hipX + 0.08, 0.6)
        return j
    }
}

final class ExchangeTrackerTests: XCTestCase {
    private var tracker = ExchangeTracker()
    private var t = 0
    private var events: [ExchangeTracker.Event] = []

    override func setUp() { tracker = ExchangeTracker(); t = 0; events = [] }

    private func step(_ body: Body, frames: Int = 1) {
        for _ in 0..<frames { t += 90; events += tracker.feed(timeMs: t, joints: body.joints()) }
    }
    private var exchanges: [LabeledExchange] { events.compactMap { if case .exchange(let e) = $0 { return e } else { return nil } } }

    private func jab(_ body: inout Body) {
        let guardPos = body.lead
        body.lead = (0.18, 0.33); step(body)        // fast extension: about 1.1 shoulder widths from the shoulder
        body.lead = guardPos; step(body)            // back to the face
    }
    private func cross(_ body: inout Body) {
        let guardPos = body.rear
        body.rear = (0.80, 0.32); step(body)
        body.rear = guardPos; step(body)
    }

    func testCleanJabIsAProbeWithResetAndNoFaults() {
        var body = Body()
        step(body, frames: 5)
        jab(&body)
        step(body, frames: 25)                      // settle in guard
        XCTAssertEqual(exchanges.count, 1)
        let e = exchanges[0]
        XCTAssertEqual(e.punches.map(\.hand), ["lead"])
        XCTAssertEqual(e.opener, "probe")
        XCTAssertTrue(e.reset)
        XCTAssertEqual(e.faults, [])
    }

    func testJabWithRearHandDroppedIsFlagged() {
        var body = Body()
        step(body, frames: 5)
        body.rear = (0.55, 0.50)                    // rear hand far below the shoulder line
        jab(&body)
        body.rear = (0.55, 0.30)
        step(body, frames: 25)
        XCTAssertEqual(exchanges.count, 1)
        XCTAssertTrue(exchanges[0].faults.contains("rear_hand_low"))
    }

    func testCombinationWithoutResetOrExit() {
        var body = Body()
        step(body, frames: 5)
        jab(&body); cross(&body)
        for _ in 0..<8 { body.lead.1 += 0.03; body.rear.1 += 0.03; step(body) }   // hands sink slowly and stay down
        step(body, frames: 20)
        XCTAssertEqual(exchanges.count, 1)
        let e = exchanges[0]
        XCTAssertEqual(e.punches.map(\.hand), ["lead", "rear"])
        XCTAssertFalse(e.reset)
        XCTAssertEqual(Set(e.faults), ["no_reset", "no_exit"])
        var policy = ExchangeCuePolicy()
        XCTAssertEqual(policy.cue(for: e, nowMs: t), "reset_guard")
        XCTAssertNil(policy.cue(for: e, nowMs: t + 1000), "cooldown holds the next cue")
    }

    func testCombinationWithExitOffTheLine() {
        var body = Body()
        step(body, frames: 5)
        jab(&body); cross(&body)
        for _ in 0..<5 { body.hipX += 0.03; step(body) }     // step off the line, hands up
        step(body, frames: 20)
        XCTAssertEqual(exchanges.count, 1)
        XCTAssertTrue(exchanges[0].exitOffLine)
        XCTAssertFalse(exchanges[0].faults.contains("no_exit"))
    }

    func testRoundSummaryEncodesSnakeCase() throws {
        let summary = RoundSummary(requestID: "r1", language: "fr", stance: "orthodox", drillID: nil, round: 1, durationS: 180, exchanges: [])
        let json = String(data: try JSONEncoder().encode(summary), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"request_id\":\"r1\""))
        XCTAssertTrue(json.contains("\"duration_s\":180"))
    }

    func testOcclusionAfterPunchIsUnobservableAndNeverRequestsResetCue() throws {
        var body = Body()
        step(body, frames: 5); jab(&body)
        for _ in 0..<20 { t += 90; events += tracker.feed(timeMs: t, joints: []) }
        let exchange = try XCTUnwrap(exchanges.first)
        XCTAssertEqual(exchange.resetEvidence?.status, .unobservable)
        XCTAssertFalse(exchange.faults.contains("no_reset"))
        var policy = ExchangeCuePolicy()
        XCTAssertNil(policy.cue(for: exchange, nowMs: t))
    }

    func testTrackingGapPreventsNegativeResetEvenAfterVisibleLowHands() throws {
        var body = Body()
        step(body, frames: 5); jab(&body)
        body.lead.1 = 0.5; body.rear.1 = 0.5
        t += 500; events += tracker.feed(timeMs: t, joints: body.joints())
        step(body, frames: 20)
        let exchange = try XCTUnwrap(exchanges.first)
        XCTAssertEqual(exchange.resetEvidence?.status, .unobservable)
        XCTAssertLessThan(exchange.resetEvidence!.observedDurationMs, 1600)
        XCTAssertFalse(exchange.resetNotDetected)
    }

    func testObservedResetSurvivesLaterMovementAndOcclusion() throws {
        var body = Body()
        step(body, frames: 5); jab(&body); step(body, frames: 3)
        // Small movement does not create another punch, but leaves the guard.
        for _ in 0..<8 { body.lead.1 += 0.03; body.rear.1 += 0.03; step(body) }
        for _ in 0..<20 { t += 90; events += tracker.feed(timeMs: t, joints: []) }
        let exchange = try XCTUnwrap(exchanges.first)
        XCTAssertEqual(exchange.resetEvidence?.status, .observed)
        XCTAssertNotNil(exchange.resetMs)
        XCTAssertFalse(exchange.faults.contains("no_reset"))
    }

    func testRoundEndingBeforeResetWindowAbstains() throws {
        var body = Body()
        step(body, frames: 5); jab(&body)
        events += tracker.finish(atMs: t)
        let exchange = try XCTUnwrap(exchanges.first)
        XCTAssertEqual(exchange.resetEvidence?.status, .unobservable)
        XCTAssertFalse(exchange.resetNotDetected)
    }

    func testCompleteVisibleNonResetCarriesEvidenceAndSurvivesSerialization() throws {
        var body = Body()
        step(body, frames: 5); jab(&body)
        for _ in 0..<8 { body.lead.1 += 0.03; body.rear.1 += 0.03; step(body) }
        step(body, frames: 20)
        let exchange = try XCTUnwrap(exchanges.first)
        XCTAssertEqual(exchange.resetEvidence?.status, .notDetected)
        XCTAssertEqual(exchange.resetEvidence?.observedDurationMs, 1600)
        XCTAssertTrue(exchange.resetNotDetected)
        let decoded = try JSONDecoder().decode(LabeledExchange.self, from: JSONEncoder().encode(exchange))
        XCTAssertEqual(decoded.resetEvidence, exchange.resetEvidence)
        XCTAssertTrue(decoded.resetNotDetected)
        var legacy = exchange
        legacy.resetEvidence = nil
        let legacyDecoded = try JSONDecoder().decode(LabeledExchange.self, from: JSONEncoder().encode(legacy))
        XCTAssertFalse(legacyDecoded.resetNotDetected)
        XCTAssertFalse(legacyDecoded.faults.contains("no_reset"))
    }
}
