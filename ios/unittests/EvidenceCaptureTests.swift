import XCTest
@testable import Coin

final class EvidenceCaptureTests: XCTestCase {
    private func exchange() -> LabeledExchange {
        LabeledExchange(id: 3, startMs: 1000, endMs: 1600,
                        punches: [ExchangePunch(hand: "lead", atMs: 1000, peakSpeed: 9, rearHandLow: true),
                                  ExchangePunch(hand: "rear", atMs: 1600, peakSpeed: 10, rearHandLow: false)],
                        opener: "probe", resetMs: nil, lateralShift: 0.1, cue: nil)
    }

    func testEachFaultPicksTheMomentThatShowsIt() {
        let e = exchange()
        XCTAssertEqual(EvidenceRenderer.moment(for: "rear_hand_low", in: e), 1000)
        XCTAssertEqual(EvidenceRenderer.moment(for: "no_reset", in: e), 3100)
        XCTAssertEqual(EvidenceRenderer.moment(for: "no_exit", in: e), 2500)
    }

    func testCardsAreRenderedFromTheRing() throws {
        let ring = EvidenceRing()
        let context = CGContext(data: nil, width: 90, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = try XCTUnwrap(context.makeImage())
        var joints = Array(repeating: PoseJoint(x: 0.5, y: 0.5, visibility: 0.9), count: 33)
        joints[16] = PoseJoint(x: 0.6, y: 0.7, visibility: 0.9)
        for t in stride(from: 0, through: 4000, by: 250) { ring.add(t: t, image: image); ring.setJoints(t: t, joints: joints) }
        let cards = EvidenceRenderer.cards(for: exchange(), ring: ring, language: "en", stance: "orthodox")
        XCTAssertEqual(Set(cards.map(\.fault)), ["rear_hand_low", "no_reset", "no_exit"])
        XCTAssertEqual(cards.first?.image.size, CGSize(width: 90, height: 160))
    }
}
