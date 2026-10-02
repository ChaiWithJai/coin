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
    @Published private(set) var sending = false
    @Published private(set) var failed = false
    private var pending: [RoundSummary] = []

    func submit(_ summary: RoundSummary) {
        pending.append(summary)
        flush()
    }

    func flush() {
        guard !sending, let next = pending.first else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                let report = try await send(next)
                pending.removeFirst()
                latest = report
                failed = false
                if !pending.isEmpty { flush() }
            } catch {
                failed = true
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
              url.scheme == "https" || (url.scheme == "http" && url.host == "127.0.0.1") else { throw URLError(.badURL) }
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
