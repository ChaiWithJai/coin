import Foundation
import AVFoundation
import Vision
import CoreML

// Conservative guard analysis. Proposes candidates for the boxer to confirm; never a verdict.
// Pure logic (GuardAnalyzer) is separate from extraction (ClipPoseExtractor) so it can be tested on frames.
// Pose alone cannot tell boxing from hand wrapping (see learning-notes.md), so the caller supplies round bounds.

struct Joint: Codable { var x: Double; var y: Double; var confidence: Double }   // Vision normalized, origin bottom-left

struct PoseFrame: Codable {
    var timeMs: Int
    var people: [[String: Joint]]   // joint name -> point, one dictionary per detected person
    var aspect: Double?             // image width / height; normalized x is multiplied by this before measuring distances
}

struct PoseWindow: Codable {
    var sequence: Int
    var startMs: Int
    var endMs: Int
    var sampledFrames: Int
    var usableFrames: Int
    var rearLowFrames: Int
    var abstain: String?            // nil when the window had enough evidence to judge
}

struct GuardCandidate: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: String                // "rear_hand_low"
    var startSeconds: Double
    var endSeconds: Double
    var confidence: Double
    var decision: String?           // nil, "confirmed", "rejected"
}

struct GuardAnalysis: Codable {
    static let version = "guard-analyzer-v3"
    var analyzerVersion = GuardAnalysis.version
    var stance: String
    var windows: [PoseWindow]
    var candidates: [GuardCandidate]
    var coverage: Double { windows.isEmpty ? 0 : Double(windows.filter { $0.abstain == nil }.count) / Double(windows.count) }
    /// The most common reason windows could not be judged, used for framing advice.
    var mainIssue: String? {
        let reasons = windows.compactMap(\.abstain)
        return Dictionary(grouping: reasons, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
}

struct GuardAnalyzer {
    var stance = "orthodox"         // orthodox: rear hand is the right hand
    var windowMs = 1000
    var minJointConfidence = 0.3
    // Provisional, from one development video: gloved guard frames median 0.22 (p90 0.26); one likely drop 0.35.
    // Vision places the wrist at the glove cuff, so a correct guard still sits below the shoulder line.
    var lowDropScale = 0.32
    var minUsableFraction = 0.6     // otherwise the window abstains
    var minLowFraction = 0.7        // share of usable frames with the rear hand low
    var minScale = 0.08             // v1 used 0.03 and measured a distant gym-goer after the camera swung
    var maxScale = 0.9              // shoulders spanning most of the frame means the phone is too close

    enum FrameResult { case noPerson, multiplePeople, hidden, tooSmall, tooClose, measured(low: Bool, confidence: Double) }

    func evaluate(_ frame: PoseFrame) -> FrameResult {
        let aspect = frame.aspect ?? 1
        let sized = frame.people.map { ($0, extent($0, aspect)) }.sorted { $0.1 > $1.1 }
        guard let (person, size) = sized.first, size > 0 else { return .noPerson }
        // No identity tracking yet: a second body of comparable size means we cannot know who the boxer is.
        if sized.count > 1 && sized[1].1 > 0.6 * size { return .multiplePeople }
        let side = stance == "southpaw" ? "left" : "right"
        func point(_ name: String) -> Joint? { person[name].flatMap { $0.confidence >= minJointConfidence ? $0 : nil } }
        guard let ls = point("leftShoulder"), let rs = point("rightShoulder") else {
            return point("nose") != nil ? .tooClose : .hidden
        }
        guard let wrist = point(side + "Wrist") else { return .hidden }
        let shoulderY = (ls.y + rs.y) / 2
        var scale = hypot((ls.x - rs.x) * aspect, ls.y - rs.y)
        // Side-on framing collapses shoulder width; fall back to half the torso length when hips are visible.
        if let lh = point("leftHip"), let rh = point("rightHip") { scale = max(scale, 0.5 * (shoulderY - (lh.y + rh.y) / 2)) }
        guard scale >= minScale else { return .tooSmall }
        guard scale <= maxScale else { return .tooClose }
        let low = shoulderY - wrist.y > lowDropScale * scale
        return .measured(low: low, confidence: min(ls.confidence, rs.confidence, wrist.confidence))
    }

    /// Analyzes frames inside the round the boxer marked; frames outside are ignored.
    func analyze(_ frames: [PoseFrame], roundStartMs: Int = 0, roundEndMs: Int = .max) -> GuardAnalysis {
        let round = frames.filter { $0.timeMs >= roundStartMs && $0.timeMs < roundEndMs }
        guard let first = round.map(\.timeMs).min(), let last = round.map(\.timeMs).max() else { return GuardAnalysis(stance: stance, windows: [], candidates: []) }
        var windows: [PoseWindow] = []
        var confidences: [Int: Double] = [:]
        for (sequence, start) in stride(from: first, through: last, by: windowMs).enumerated() {
            let inWindow = round.filter { $0.timeMs >= start && $0.timeMs < start + windowMs }
            var usable = 0, low = 0, reasons: [String: Int] = [:], lowConfidence = 0.0
            for frame in inWindow {
                switch evaluate(frame) {
                case .noPerson: reasons["no_person", default: 0] += 1
                case .multiplePeople: reasons["multiple_people", default: 0] += 1
                case .hidden: reasons["joints_hidden", default: 0] += 1
                case .tooSmall: reasons["boxer_too_small", default: 0] += 1
                case .tooClose: reasons["too_close", default: 0] += 1
                case .measured(let isLow, let confidence):
                    usable += 1
                    if isLow { low += 1; lowConfidence += confidence }
                }
            }
            var abstain: String?
            if inWindow.isEmpty { abstain = "no_frames" }
            else if Double(usable) < minUsableFraction * Double(inWindow.count) { abstain = reasons.max { $0.value < $1.value }?.key ?? "insufficient_evidence" }
            windows.append(PoseWindow(sequence: sequence, startMs: start, endMs: start + windowMs, sampledFrames: inWindow.count, usableFrames: usable, rearLowFrames: low, abstain: abstain))
            if low > 0 { confidences[sequence] = lowConfidence / Double(usable) }
        }
        // Merge consecutive qualifying windows into one candidate moment.
        var candidates: [GuardCandidate] = []
        var run: [PoseWindow] = []
        func flush() {
            guard let first = run.first, let end = run.last else { return }
            let confidence = run.compactMap { confidences[$0.sequence] }.reduce(0, +) / Double(run.count)
            candidates.append(GuardCandidate(kind: "rear_hand_low", startSeconds: Double(first.startMs) / 1000, endSeconds: Double(end.endMs) / 1000, confidence: (confidence * 100).rounded() / 100))
            run = []
        }
        for window in windows {
            if window.abstain == nil && window.usableFrames > 0 && Double(window.rearLowFrames) >= minLowFraction * Double(window.usableFrames) { run.append(window) } else { flush() }
        }
        flush()
        return GuardAnalysis(stance: stance, windows: windows, candidates: candidates)
    }

    private func extent(_ person: [String: Joint], _ aspect: Double) -> Double {
        let points = person.values.filter { $0.confidence >= minJointConfidence }
        guard points.count >= 2 else { return 0 }
        return (points.map(\.x).max()! - points.map(\.x).min()!) * aspect + (points.map(\.y).max()! - points.map(\.y).min()!)
    }
}

enum ClipPoseExtractor {
    static let jointNames: [VNHumanBodyPoseObservation.JointName: String] = [
        .nose: "nose", .neck: "neck", .leftShoulder: "leftShoulder", .rightShoulder: "rightShoulder",
        .leftElbow: "leftElbow", .rightElbow: "rightElbow", .leftWrist: "leftWrist", .rightWrist: "rightWrist",
        .leftHip: "leftHip", .rightHip: "rightHip"]

    /// Samples the clip at `fps` and runs Apple Vision body pose on each frame, on device.
    static func frames(url: URL, fps: Double = 10, maxSeconds: Double = 600, progress: ((Double) -> Void)? = nil) async throws -> [PoseFrame] {
        let asset = AVURLAsset(url: url)
        let duration = min(try await asset.load(.duration).seconds, maxSeconds)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        var result: [PoseFrame] = []
        for t in stride(from: 0.0, to: duration, by: 1 / fps) {
            try Task.checkCancellation()
            let image = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
            let request = VNDetectHumanBodyPoseRequest()
            #if targetEnvironment(simulator)
            // The simulator has no Neural Engine context for Vision pose; run on CPU there only.
            if #available(iOS 17.0, macOS 14.0, *), let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { return true } else { return false } }) {
                try request.setComputeDevice(cpu, for: .main)
            }
            #endif
            try VNImageRequestHandler(cgImage: image).perform([request])
            let people = (request.results ?? []).map { observation -> [String: Joint] in
                var joints: [String: Joint] = [:]
                for (key, name) in jointNames {
                    if let p = try? observation.recognizedPoint(key), p.confidence > 0 { joints[name] = Joint(x: Double(p.location.x), y: Double(p.location.y), confidence: Double(p.confidence)) }
                }
                return joints
            }
            result.append(PoseFrame(timeMs: Int((t * 1000).rounded()), people: people, aspect: Double(image.width) / Double(max(image.height, 1))))
            progress?(t / duration)
        }
        return result
    }
}
