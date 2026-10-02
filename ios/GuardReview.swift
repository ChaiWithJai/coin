import SwiftUI
import AVKit

/// An immutable decision snapshot survives re-analysis. Simulator decisions are development evidence.
struct GuardLabel: Codable, Identifiable {
    var id = UUID()
    let candidateID: UUID
    let sessionID: UUID
    let analyzerVersion: String
    let stance: String
    let startSeconds: Double
    let endSeconds: Double
    let roundStart: Double?
    let roundEnd: Double?
    let kind: String
    let confirmed: Bool
    let recordedAt: Date
    let source: String
    let eligibleForTraining: Bool
}

extension FilmStore {
    func setRoundBound(_ id: UUID, start: Double? = nil, end: Double? = nil) {
        guard let index = rounds.firstIndex(where: { $0.id == id }) else { return }
        if let start { rounds[index].roundStart = max(0, start) }
        if let end { rounds[index].roundEnd = max(0, end) }
        save()
    }
    func saveAnalysis(_ id: UUID, analysis: GuardAnalysis) {
        guard let index = rounds.firstIndex(where: { $0.id == id }) else { return }
        rounds[index].guardAnalysis = analysis; save()
    }
    /// A confirmed candidate becomes a user note, so only boxer-confirmed observations ever reach Bonsai.
    func decide(_ id: UUID, candidate: UUID, confirmed: Bool, french: Bool) {
        guard let index = rounds.firstIndex(where: { $0.id == id }),
              let c = rounds[index].guardAnalysis?.candidates.firstIndex(where: { $0.id == candidate }),
              rounds[index].guardAnalysis?.candidates[c].decision == nil else { return }
        guard let analysis = rounds[index].guardAnalysis else { return }
        let proposal = analysis.candidates[c]
        #if targetEnvironment(simulator)
        let source = "simulator_development"
        #else
        let source = "device_review_unverified"
        #endif
        let label = GuardLabel(candidateID: proposal.id, sessionID: id,
            analyzerVersion: analysis.analyzerVersion, stance: analysis.stance,
            startSeconds: proposal.startSeconds, endSeconds: proposal.endSeconds,
            roundStart: rounds[index].roundStart, roundEnd: rounds[index].roundEnd,
            kind: proposal.kind, confirmed: confirmed, recordedAt: Date(), source: source,
            eligibleForTraining: false)
        if rounds[index].guardLabels == nil { rounds[index].guardLabels = [] }
        rounds[index].guardLabels?.append(label)
        rounds[index].guardAnalysis?.candidates[c].decision = confirmed ? "confirmed" : "rejected"
        if confirmed, let start = rounds[index].guardAnalysis?.candidates[c].startSeconds {
            rounds[index].notes.append(FilmNote(seconds: start, text: TrainingCopy.text("guard_confirmed_note", french ? "fr" : "en")))
        }
        save()
    }
}

enum GuardCopy {
    static func advice(_ issue: String?, _ french: Bool) -> String {
        let known = ["no_person", "too_close", "joints_hidden", "boxer_too_small", "multiple_people"]
        let key = issue.flatMap { known.contains($0) ? "guard_advice_\($0)" : nil } ?? "guard_advice_default"
        return TrainingCopy.text(key, french ? "fr" : "en")
    }
}

struct GuardReviewSection: View {
    @EnvironmentObject var store: FilmStore
    @AppStorage("stance") private var stance = "orthodox"
    let round: Round
    let french: Bool
    let player: AVPlayer?
    @State private var working = false
    @State private var progress = 0.0
    @State private var failed = false
    @State private var failure = ""

    func clock(_ s: Double) -> String { String(format: "%02d:%02d", Int(s) / 60, Int(s) % 60) }
    private var language: String { french ? "fr" : "en" }
    private func copy(_ key: String) -> String { TrainingCopy.text(key, language) }
    private func format(_ key: String, _ values: CVarArg...) -> String { String(format: copy(key), arguments: values) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(copy("guard_title")).font(.headline)
            Text(copy("guard_instruction"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(format("guard_start", clock(round.roundStart ?? 0))) {
                    store.setRoundBound(round.id, start: player?.currentTime().seconds ?? 0)
                }
                Spacer()
                Button(format("guard_end", round.roundEnd.map(clock) ?? "—")) {
                    store.setRoundBound(round.id, end: player?.currentTime().seconds ?? 0)
                }
            }.buttonStyle(.bordered).font(.caption)
            Button {
                Task { await analyse() }
            } label: {
                if working { ProgressView(value: progress).frame(maxWidth: .infinity) }
                else { Label(copy("guard_analyse"), systemImage: "figure.boxing") }
            }.disabled(working)
            if failed { Text(copy("guard_analysis_failed") + failure).font(.caption).foregroundStyle(.red) }
            if let analysis = round.guardAnalysis {
                Text(format("guard_coverage", Int((analysis.coverage * 100).rounded()))).font(.subheadline.bold())
                if analysis.coverage < 0.6 { Text(GuardCopy.advice(analysis.mainIssue, french)).font(.caption) }
                if analysis.coverage > 0 && analysis.candidates.isEmpty {
                    Text(copy("guard_no_candidates")).font(.caption)
                }
                ForEach(analysis.candidates) { c in
                    HStack {
                        Button { player?.seek(to: CMTime(seconds: c.startSeconds, preferredTimescale: 600)) } label: {
                            VStack(alignment: .leading) {
                                Text("\(clock(c.startSeconds))–\(clock(c.endSeconds))").monospacedDigit()
                                Text(copy("guard_candidate")).font(.caption)
                            }
                        }
                        Spacer()
                        if let decision = c.decision {
                            Text(copy(decision == "confirmed" ? "guard_confirmed" : "guard_rejected")).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button(copy("guard_yes")) { store.decide(round.id, candidate: c.id, confirmed: true, french: french) }.buttonStyle(.borderedProminent)
                            Button(copy("guard_no")) { store.decide(round.id, candidate: c.id, confirmed: false, french: french) }.buttonStyle(.bordered)
                        }
                    }
                }
                Text(copy("guard_limit")).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    func analyse() async {
        working = true; failed = false; progress = 0
        defer { working = false }
        let url = store.folder.appendingPathComponent(round.filename)
        let start = Int(((round.roundStart ?? 0) * 1000).rounded())
        let end = round.roundEnd.map { Int(($0 * 1000).rounded()) } ?? .max
        let stance = stance
        do {
            let frames = try await Task.detached(priority: .userInitiated) { () -> [PoseFrame] in
                #if DEBUG && targetEnvironment(simulator)
                // Vision body pose cannot run in the simulator. Poses extracted on macOS by the same extractor may sit beside the clip.
                let sidecar = url.appendingPathExtension("poses.json")
                if FileManager.default.fileExists(atPath: sidecar.path) { return try JSONDecoder().decode([PoseFrame].self, from: Data(contentsOf: sidecar)) }
                #endif
                return try await ClipPoseExtractor.frames(url: url) { value in Task { @MainActor in progress = value } }
            }.value
            store.saveAnalysis(round.id, analysis: GuardAnalyzer(stance: stance).analyze(frames, roundStartMs: start, roundEndMs: end))
        } catch {
            failed = true
            #if DEBUG
            failure = " (\(error))"
            #endif
        }
    }
}
