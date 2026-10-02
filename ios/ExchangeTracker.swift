import Foundation

// Live exchange labeling from MediaPipe pose (33 landmarks, image-normalized, y grows downward).
// Pure logic, fed one frame at a time, so it runs on the phone and is testable with synthetic frames.
// Taxonomy (master plan, section 2): exchange phases initiate / interact / terminate / reset;
// faults rear hand low, no reset, no exit off the line; opener probe vs commit.

struct ExchangePunch: Codable, Equatable {
    var hand: String            // "lead" or "rear"
    var atMs: Int
    var peakSpeed: Double       // shoulder widths per second
    var rearHandLow: Bool       // lead-hand punch thrown with the rear hand below the guard line
}

struct LabeledExchange: Codable, Equatable, Identifiable {
    var id: Int
    var startMs: Int            // initiate: first punch onset
    var endMs: Int              // terminate: last punch onset
    var punches: [ExchangePunch]
    var opener: String          // "probe" (lead hand first) or "commit" (rear hand first)
    var resetMs: Int?           // reset: time from the last punch back to guard; nil = no reset seen
    var lateralShift: Double    // hip-center lateral travel after the last punch, in shoulder widths
    var cue: String?            // the live cue spoken for this exchange, if any

    var rearHandLow: Bool { punches.contains { $0.rearHandLow } }
    var reset: Bool { resetMs != nil }
    var exitOffLine: Bool { lateralShift >= ExchangeTracker.exitShift }
    var faults: [String] {
        var result: [String] = []
        if rearHandLow { result.append("rear_hand_low") }
        if !reset { result.append("no_reset") }
        if punches.count >= 2 && !exitOffLine { result.append("no_exit") }
        return result
    }
}

struct ExchangeTracker {
    // Thresholds are starting points for the gym test, not tuned values.
    static let exitShift = 0.35         // shoulder widths of lateral hip travel that counts as leaving the line
    var stance = "orthodox"             // orthodox: lead = left hand
    var onsetSpeed = 4.5                // wrist speed (shoulder widths / s) that starts a punch
    var minExtension = 0.85             // wrist-to-own-shoulder distance (shoulder widths) at the onset
    var refractoryMs = 280              // per hand, so one punch is not counted twice
    var exchangeGapMs = 1100            // a pause this long ends the exchange
    var resetWindowMs = 1600            // time allowed after the last punch to get back to guard
    var guardLowScale = 0.32            // wrist this far below the shoulder line (shoulder widths) = hand low
    var settledSpeed = 1.2              // both wrists slower than this = settled in guard

    private struct Frame { var t: Int; var lead: (Double, Double); var rear: (Double, Double)
                           var leadShoulder: (Double, Double); var rearShoulder: (Double, Double)
                           var hip: (Double, Double); var shoulderY: Double; var scale: Double }
    private var previous: Frame?
    private var lastOnset: [String: Int] = [:]
    private var current: (start: Int, punches: [ExchangePunch], hipStart: Double)?
    private var settledSince: Int?
    private var maxShift = 0.0
    private var nextID = 1
    private(set) var exchanges: [LabeledExchange] = []

    enum Event: Equatable { case punch(ExchangePunch), exchange(LabeledExchange) }

    /// Feed one pose frame. Returns punches as they start and exchanges when they finish.
    mutating func feed(timeMs: Int, joints: [PoseJoint]) -> [Event] {
        guard let frame = makeFrame(timeMs, joints) else { previous = nil; return closeIfDue(timeMs) }
        defer { previous = frame }
        var events: [Event] = []
        if let prev = previous, frame.t > prev.t, frame.t - prev.t <= 400 {
            let dt = Double(frame.t - prev.t) / 1000
            let speeds = ["lead": speed(prev.lead, frame.lead, prev.hip, frame.hip, frame.scale, dt),
                          "rear": speed(prev.rear, frame.rear, prev.hip, frame.hip, frame.scale, dt)]
            for hand in ["lead", "rear"] {
                let wrist = hand == "lead" ? frame.lead : frame.rear
                let shoulder = hand == "lead" ? frame.leadShoulder : frame.rearShoulder
                let prevWrist = hand == "lead" ? prev.lead : prev.rear
                let prevShoulder = hand == "lead" ? prev.leadShoulder : prev.rearShoulder
                let ext = dist(wrist, shoulder) / frame.scale
                let prevExt = dist(prevWrist, prevShoulder) / frame.scale
                guard speeds[hand]! >= onsetSpeed, ext >= minExtension, ext > prevExt,
                      frame.t - (lastOnset[hand] ?? .min / 2) >= refractoryMs else { continue }
                lastOnset[hand] = frame.t
                let punch = ExchangePunch(hand: hand, atMs: frame.t, peakSpeed: (speeds[hand]! * 10).rounded() / 10,
                                          rearHandLow: hand == "lead" && frame.rear.1 - frame.shoulderY > guardLowScale * frame.scale)
                if current == nil { current = (frame.t, [], frame.hip.0); maxShift = 0 }
                current!.punches.append(punch)
                settledSince = nil
                events.append(.punch(punch))
            }
            if let open = current {
                let lastPunch = open.punches.last!.atMs
                if frame.t > lastPunch {
                    maxShift = max(maxShift, abs(frame.hip.0 - open.hipStart) / frame.scale)
                    let wrists: [(Double, Double)] = [frame.lead, frame.rear]
                    let inGuard = wrists.allSatisfy { $0.1 - frame.shoulderY <= guardLowScale * frame.scale }
                    let settled = inGuard && speeds.values.allSatisfy { $0 < settledSpeed }
                    if settled { if settledSince == nil { settledSince = frame.t } } else { settledSince = nil }
                }
            }
        }
        return events + closeIfDue(frame.t)
    }

    /// Close any open exchange (call at the end of a round).
    mutating func finish(atMs: Int) -> [Event] { closeIfDue(atMs, force: true) }

    private mutating func closeIfDue(_ t: Int, force: Bool = false) -> [Event] {
        guard let open = current, let last = open.punches.last?.atMs else { return [] }
        guard force || t - last >= max(exchangeGapMs, resetWindowMs) else { return [] }
        let resetAt = settledSince.flatMap { $0 - last <= resetWindowMs ? $0 - last : nil }
        let exchange = LabeledExchange(id: nextID, startMs: open.start, endMs: last, punches: open.punches,
                                       opener: open.punches.first!.hand == "lead" ? "probe" : "commit",
                                       resetMs: resetAt, lateralShift: (maxShift * 100).rounded() / 100, cue: nil)
        nextID += 1
        current = nil; settledSince = nil; maxShift = 0
        exchanges.append(exchange)
        return [.exchange(exchange)]
    }

    private func makeFrame(_ t: Int, _ j: [PoseJoint]) -> Frame? {
        guard j.count > 24, [11, 12, 15, 16, 23, 24].allSatisfy({ j[$0].inFrame }) else { return nil }
        let (leadW, rearW, leadS, rearS) = stance == "southpaw" ? (16, 15, 12, 11) : (15, 16, 11, 12)
        let scale = hypot(j[11].x - j[12].x, j[11].y - j[12].y)
        guard scale >= 0.06 else { return nil }
        func p(_ i: Int) -> (Double, Double) { (j[i].x, j[i].y) }
        return Frame(t: t, lead: p(leadW), rear: p(rearW), leadShoulder: p(leadS), rearShoulder: p(rearS),
                     hip: ((j[23].x + j[24].x) / 2, (j[23].y + j[24].y) / 2), shoulderY: (j[11].y + j[12].y) / 2, scale: scale)
    }
    private func speed(_ a: (Double, Double), _ b: (Double, Double), _ ha: (Double, Double), _ hb: (Double, Double), _ scale: Double, _ dt: Double) -> Double {
        hypot((b.0 - hb.0) - (a.0 - ha.0), (b.1 - hb.1) - (a.1 - ha.1)) / scale / dt
    }
    private func dist(_ a: (Double, Double), _ b: (Double, Double)) -> Double { hypot(a.0 - b.0, a.1 - b.1) }
}

/// One live cue per exchange at most, with a cooldown. Priorities follow the taxonomy's training value for solo work.
struct ExchangeCuePolicy {
    var cooldownMs = 6000
    private var lastCueMs = Int.min / 2
    private var commitStreak = 0

    static let lines: [String: [String: String]] = [
        "reset_guard": ["fr": "Reviens en garde.", "en": "Back to guard."],
        "rear_hand_up": ["fr": "Main arrière au visage.", "en": "Rear hand to your face."],
        "exit_reset": ["fr": "Sors de la ligne. Reprends ta place.", "en": "Leave the line. Reset your position."],
        "probe_first": ["fr": "Ouvre avec le jab.", "en": "Open with the jab."],
    ]

    mutating func cue(for exchange: LabeledExchange, nowMs: Int) -> String? {
        commitStreak = exchange.opener == "commit" ? commitStreak + 1 : 0
        guard nowMs - lastCueMs >= cooldownMs else { return nil }
        let pick: String?
        if !exchange.reset { pick = "reset_guard" }
        else if exchange.rearHandLow { pick = "rear_hand_up" }
        else if exchange.punches.count >= 2 && !exchange.exitOffLine { pick = "exit_reset" }
        else if commitStreak >= 3 { pick = "probe_first"; commitStreak = 0 }
        else { pick = nil }
        if pick != nil { lastCueMs = nowMs }
        return pick
    }
}

/// What the phone sends to the harness at the end of a round.
struct RoundSummary: Codable {
    var requestID: String
    var language: String
    var stance: String
    var drillID: String?
    var round: Int
    var durationS: Int
    var exchanges: [LabeledExchange]

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", language, stance, drillID = "drill_id", round, durationS = "duration_s", exchanges
    }
}
