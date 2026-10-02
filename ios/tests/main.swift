import Foundation
let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: folder) }
let snapshot: [String: Any] = ["session_id": UUID().uuidString, "language": "fr", "notes": [["seconds": 12, "text": "fixture"]]]
let first = try ReviewRequestStore(folder: folder).body(snapshot: snapshot, endpoint: "https://example.test/v1/review")
let restored = try ReviewRequestStore(folder: folder).body(snapshot: snapshot, endpoint: "https://example.test/v1/review")
precondition(first == restored, "Restart must reuse exact request")
var changed = snapshot; changed["language"] = "en"
let second = try ReviewRequestStore(folder: folder).body(snapshot: changed, endpoint: "https://example.test/v1/review")
precondition(first != second, "Changed evidence must be a new request")
let other = try ReviewRequestStore(folder: folder).body(snapshot: snapshot, endpoint: "https://other.test/v1/review")
precondition(first != other, "Different endpoint must be separate")
print("PASS: restart retry, changed snapshot, endpoint isolation")
let english = CoachingCopy.drills["review_clip"]!["en"]!
let french = CoachingCopy.drills["review_clip"]!["fr"]!
precondition(CoachingCopy.drill(id: nil, original: french, language: "en") == english)
precondition(CoachingCopy.drill(id: "review_clip", original: english, language: "fr") == french)
precondition(CoachingCopy.drill(id: nil, original: "Unknown legacy generation", language: "fr") == nil)
print("PASS: legacy review translation, selected language, unknown legacy fallback")
