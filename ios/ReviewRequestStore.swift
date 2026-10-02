import Foundation
import CryptoKit

/// Persist the exact request before sending it. A lost response must reuse its ID.
struct ReviewRequestStore {
    let folder: URL

    func body(snapshot: [String: Any], endpoint: String) throws -> Data {
        let canonical = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
        var identity = Data(endpoint.utf8)
        identity.append(0)
        identity.append(canonical)
        let key = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent(key + ".json")
        if FileManager.default.fileExists(atPath: path.path) {
            let existing = try Data(contentsOf: path)
            guard let object = try JSONSerialization.jsonObject(with: existing) as? [String: Any],
                  let id = object["request_id"] as? String, UUID(uuidString: id) != nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return existing
        }
        var request = snapshot
        request["request_id"] = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        try data.write(to: path, options: .atomic)
        return data
    }
}
