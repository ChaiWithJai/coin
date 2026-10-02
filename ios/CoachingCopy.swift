import Foundation

enum CoachingCopy {
    static let drills: [String: [String: String]] = [
        "guard_return": ["fr": "Au ralenti, fais un jab isolé en gardant la main arrière près du visage. Reviens à ta garde de départ avant de recommencer. Vérifie ce point avec ton coach.", "en": "Slowly throw one jab while keeping your rear hand near your face. Return to your starting guard before repeating. Check this focus with your coach."],
        "review_clip": ["fr": "Revois ce passage au ralenti et note ce qui est clairement visible. Choisis avec ton coach un seul point à travailler avant de modifier ta technique.", "en": "Replay this moment slowly and note what is clearly visible. Choose one focus with your coach before changing your technique."],
    ]
    static func drill(id: String?, original: String, language: String) -> String? {
        let resolved = id ?? drills.first(where: { $0.value.values.contains(original) })?.key
        return resolved.flatMap { drills[$0]?[language] }
    }
}
