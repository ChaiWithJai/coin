import Foundation
import SwiftUI

struct SavedRoundReview: Identifiable {
    var id: String
    var round: Int
    var title: String?
    var language: String
    var report: RoundReport?
}

/// The harness's answer for one round: small-model labels per exchange plus the large model's report.
struct RoundReport: Codable, Equatable {
    struct ExchangeLabel: Codable, Equatable {
        var id: Int
        var opener: String           // probe / commit, as judged by the small model
        var intervention: String     // cue / quiet / review
        var confidence: Double
    }
    var observation: String
    var interpretation: String
    var constraint: String          // the one thing to do next round
    var prediction: String
    var drill: String
    var labels: [ExchangeLabel]
    var models: [String]
    var latencyMs: Int

    enum CodingKeys: String, CodingKey {
        case observation, interpretation, constraint, prediction, drill, labels, models, latencyMs = "latency_ms"
    }
}

/// Sends a finished round to the harness. Never blocks the workout; failures leave the round summary for a retry.
@MainActor final class RoundReportClient: ObservableObject {
    @Published private(set) var latest: RoundReport?
    private(set) var latestSessionID: String?
    private(set) var latestRound: Int?
    @Published private(set) var sending = false
    @Published private(set) var failed = false
    private var pending: [RoundSummary] = []

    init() {
        pending = Self.pendingSummaries(in: Self.folder)
    }

    static func pendingSummaries(in folder: URL) -> [RoundSummary] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasSuffix("-summary.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let summary = try? JSONDecoder().decode(RoundSummary.self, from: data),
                      UUID(uuidString: summary.requestID) != nil,
                      readReport(summary.requestID, in: folder) == nil else { return nil }
                return summary
            }
    }

    private static func readReport(_ id: String, in folder: URL) -> RoundReport? {
        guard UUID(uuidString: id) != nil,
              let data = try? Data(contentsOf: folder.appendingPathComponent("\(id)-report.json")) else { return nil }
        return try? JSONDecoder().decode(RoundReport.self, from: data)
    }

    static func savedReviews(sessionID: UUID, in folder: URL) -> [SavedRoundReview] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasSuffix("-summary.json") }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let summary = try? JSONDecoder().decode(RoundSummary.self, from: data),
                  summary.sessionID.flatMap(UUID.init(uuidString:)) == sessionID,
                  UUID(uuidString: summary.requestID) != nil else { return nil }
            return SavedRoundReview(id: summary.requestID, round: summary.round, title: summary.sourceTitle,
                                    language: summary.language, report: readReport(summary.requestID, in: folder))
        }.sorted { ($0.round, $0.id) < ($1.round, $1.id) }
    }

    #if DEBUG
    /// Local-only UI fixture: a simulator without a camera cannot produce an exchange.
    static func seedUITestReview(sessionID: UUID) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["COIN_TEST_ROUND_REVIEW"] == "1",
              environment["COIN_SERVICE_URL"] == "http://127.0.0.1:1",
              let token = environment["COIN_TRAINING_DIRECTORY"], token.hasPrefix("workout-ui-"),
              token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
              savedReviews(sessionID: sessionID, in: folder).isEmpty else { return }
        let id = UUID().uuidString
        let exchange = LabeledExchange(id: 1, startMs: 1000, endMs: 1000,
            punches: [ExchangePunch(hand: "lead", atMs: 1000, peakSpeed: 5, rearHandLow: false)],
            opener: "probe", resetMs: 300, lateralShift: 0, cue: nil)
        let summary = RoundSummary(requestID: id, language: "en", stance: "orthodox",
            drillID: "free-boxing-v1", round: 1, durationS: 10, exchanges: [exchange],
            sessionID: sessionID.uuidString, workoutMode: "freestyle", sourceTitle: "UI fixture · pending review",
            sourceID: "ui-fixture-pending-review")
        save(summary, name: "\(id)-summary")
    }
    #endif

    func submit(_ summary: RoundSummary) {
        guard Self.save(summary, name: "\(summary.requestID)-summary") else { failed = true; return }
        if !pending.contains(where: { $0.requestID == summary.requestID }) { pending.append(summary) }
        flush()
    }

    /// Everything is logged automatically on the phone, next to the server's trace.
    static let didSave = Notification.Name("CoinRoundReportSaved")
    static var folder: URL {
        var root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        if let token = ProcessInfo.processInfo.environment["COIN_TRAINING_DIRECTORY"],
           !token.isEmpty, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
            root = root.appendingPathComponent("UITests").appendingPathComponent(token)
        }
        #endif
        return root.appendingPathComponent("RoundLogs", isDirectory: true)
    }
    @discardableResult static func save<T: Encodable>(_ value: T, name: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: folder.appendingPathComponent(name + ".json"), options: .atomic)
            NotificationCenter.default.post(name: didSave, object: nil)
            return true
        } catch { return false }
    }

    func flush() {
        guard !sending, let next = pending.first else { return }
        sending = true
        Task {
            do {
                let report = try await send(next)
                guard Self.save(report, name: "\(next.requestID)-report") else {
                    throw CocoaError(.fileWriteUnknown)
                }
                pending.removeFirst()
                latestSessionID = next.sessionID
                latestRound = next.round
                latest = report
                failed = false
                sending = false
                flush()
            } catch {
                failed = true
                sending = false
            }
        }
    }

    private func send(_ summary: RoundSummary) async throws -> RoundReport {
        #if DEBUG
        if summary.sourceID == "ui-fixture-pending-review" { throw URLError(.notConnectedToInternet) }
        let environment = ProcessInfo.processInfo.environment
        let base = environment["COIN_SERVICE_URL"] ?? UserDefaults.standard.string(forKey: "serviceURL") ?? "http://127.0.0.1:5290"
        let credential = environment["COIN_SERVICE_TOKEN"] ?? ServiceCredential.load()
        #else
        let base = UserDefaults.standard.string(forKey: "serviceURL") ?? ""
        let credential = ServiceCredential.load()
        #endif
        guard let token = credential, !token.isEmpty, let url = URL(string: base + "/v1/round"),
              CoinServer.allowed(url) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(summary)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(RoundReport.self, from: data)
    }
}

/// Reviews stay with their original session and language, including the final round.
struct SavedRoundReportsView: View {
    let sessionID: UUID
    @AppStorage("language") private var language = "fr"
    @State private var reviews: [SavedRoundReview] = []
    @StateObject private var client = RoundReportClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !reviews.isEmpty {
                Text(language == "fr" ? "Retour sur les reprises" : "Round reviews")
                    .font(.headline).foregroundStyle(Noir.ink)
                ForEach(reviews) { review in
                    VStack(alignment: .leading, spacing: 7) {
                        Text((language == "fr" ? "Reprise " : "Round ") + String(review.round)
                             + " · " + review.language.uppercased())
                            .font(.caption.monospaced()).foregroundStyle(Noir.gold)
                        if let title = review.title { Text(title).font(.subheadline).foregroundStyle(Noir.ink) }
                        if let report = review.report {
                            Text(report.observation).foregroundStyle(Noir.ink)
                            Text(report.interpretation).foregroundStyle(Noir.muted)
                            Text(report.constraint).foregroundStyle(Noir.ink)
                        } else {
                            Text(language == "fr" ? "Retour en attente. Ta reprise est enregistrée sur ce téléphone."
                                 : "Review pending. Your round is saved on this phone.")
                                .foregroundStyle(Noir.muted)
                        }
                    }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).background(Noir.panel, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("saved-round-review-\(review.round)")
                }
            }
        }
        .onAppear {
            #if DEBUG
            RoundReportClient.seedUITestReview(sessionID: sessionID)
            #endif
            reload(); client.flush()
        }
        .onReceive(NotificationCenter.default.publisher(for: RoundReportClient.didSave)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            reload(); client.flush()
        }
    }

    private func reload() { reviews = RoundReportClient.savedReviews(sessionID: sessionID, in: RoundReportClient.folder) }
}
