import Foundation
import Security

struct CoachingReview: Codable {
    let observation: String
    let drill: String
    let limitation: String
    let event_id: String
    let evidence_source: String
    let model: String
    let drill_id: String?
}

enum ServiceCredential {
    static let service = "com.coinboxing.prototype"
    @discardableResult static func save(_ token: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "backend"]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    static func load() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "backend", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor final class CoachingClient: ObservableObject {
    @Published var working = false
    @Published var error: String?
    func review(round: Round, language: String) async -> CoachingReview? {
        guard !working else { return nil }
        working = true; error = nil
        defer { working = false }
        do {
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            let credential = environment["COIN_SERVICE_TOKEN"] ?? ServiceCredential.load()
            let base = environment["COIN_SERVICE_URL"] ?? UserDefaults.standard.string(forKey: "serviceURL") ?? "http://127.0.0.1:5290"
            #else
            let credential = ServiceCredential.load()
            let base = UserDefaults.standard.string(forKey: "serviceURL") ?? ""
            #endif
            guard let token = credential, !token.isEmpty, let url = URL(string: base + "/v1/review") else {
                throw NSError(domain: "Coin", code: 1, userInfo: [NSLocalizedDescriptionKey: language == "fr" ? "Connecte ton serveur dans les réglages." : "Connect your server in settings."])
            }
            guard CoinServer.allowed(url) else {
                throw NSError(domain: "Coin", code: 2, userInfo: [NSLocalizedDescriptionKey: language == "fr" ? "Utilise HTTPS pour un serveur distant." : "Use HTTPS for a remote server."])
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"; request.timeoutInterval = 100
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let notes = round.notes.suffix(10).map { ["seconds": $0.seconds, "text": $0.text] as [String: Any] }
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ReviewRequests", isDirectory: true).appendingPathComponent(round.id.uuidString, isDirectory: true)
            request.httpBody = try ReviewRequestStore(folder: folder).body(snapshot: ["session_id": round.id.uuidString, "language": language, "notes": notes], endpoint: url.absoluteString)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 409 {
                    throw NSError(domain: "Coin", code: status, userInfo: [NSLocalizedDescriptionKey: language == "fr" ? "Cette demande attend une vérification du serveur. Tes notes sont conservées." : "This request needs a server check. Your notes are saved."])
                }
                throw NSError(domain: "Coin", code: status, userInfo: [NSLocalizedDescriptionKey: language == "fr" ? "Serveur indisponible (\(status)). Tes notes sont conservées." : "Server unavailable (\(status)). Your notes are saved."])
            }
            return try JSONDecoder().decode(CoachingReview.self, from: data)
        } catch { self.error = (error as NSError).domain == "Coin" ? error.localizedDescription : (language == "fr" ? "La demande a échoué. Tes notes sont conservées. Réessaie lorsque la connexion est disponible." : "The request failed. Your notes are saved. Try again when connected."); return nil }
    }
}
