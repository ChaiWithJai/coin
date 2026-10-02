import Foundation

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
                      !FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(summary.requestID)-report.json").path) else { return nil }
                return summary
            }
    }

    func submit(_ summary: RoundSummary) {
        Self.save(summary, name: "\(summary.requestID)-summary")
        if !pending.contains(where: { $0.requestID == summary.requestID }) { pending.append(summary) }
        flush()
    }

    /// Everything is logged automatically on the phone, next to the server's trace.
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RoundLogs", isDirectory: true)
    static func save<T: Encodable>(_ value: T, name: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: folder.appendingPathComponent(name + ".json"), options: .atomic) }
    }

    func flush() {
        guard !sending, let next = pending.first else { return }
        sending = true
        Task {
            do {
                let report = try await send(next)
                Self.save(report, name: "\(next.requestID)-report")
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
