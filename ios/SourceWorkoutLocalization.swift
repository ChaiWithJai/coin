import Foundation

/// Display copy only. WorkoutCatalog remains the authority for timing, links,
/// exercise identity, and the English source text sent to round analysis.
struct SourceWorkoutFrenchOverlay: Decodable {
    private static let quantityPattern = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9])[0-9]+(?![A-Za-z0-9])")
    private static func quantities(_ text: String) -> [String] {
        let source = text as NSString
        return quantityPattern.matches(in: text, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
    }
    struct Item: Decodable {
        let itemID: String
        let sourceText: String
        let textFR: String
    }
    struct Block: Decodable {
        let blockID: String
        let sourceTitle: String
        let sourceInstructions: String
        let titleFR: String
        let instructionsFR: String
        let sourceItems: [Item]
    }
    let schemaVersion: Int
    let lessonID: String
    let sourceSHA256: String
    let sourceTitleFR: String
    let status: String
    let reviewFlags: [String: String]
    let blocks: [Block]

    /// Each future day has one explicitly bundled file named
    /// SourceFrench-<lesson-id>.json. Nothing under the proposal or batch
    /// directories is scanned at runtime.
    static func bundled(for lessonID: String) -> Self? {
        guard !lessonID.isEmpty,
              lessonID.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { return nil }
        let name = lessonID == "basic-w1-d1" ? "BasicW1D1French" : "SourceFrench-\(lessonID)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let overlay = try? JSONDecoder().decode(Self.self, from: data),
              overlay.lessonID == lessonID else { return nil }
        return overlay
    }

    // Kept for existing day-one checks; new call sites select by lesson ID.
    static var bundled: Self? { bundled(for: "basic-w1-d1") }

    /// Candidate text cannot enter a workout, and a partial overlay never
    /// mixes languages. Day one retains its explicit provisional exception.
    func validated(for lesson: WorkoutLesson) -> [String: Block]? {
        guard schemaVersion == 1,
              (status == "reviewed" || (lessonID == "basic-w1-d1" && status == "provisional")),
              lesson.id == lessonID, lesson.sourceSHA256 == sourceSHA256,
              !sourceTitleFR.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              blocks.count == lesson.blocks.count,
              Set(blocks.map(\.blockID)).count == blocks.count else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.blockID, $0) })
        let sourceItemIDs = Set(lesson.blocks.flatMap { ($0.sourceItems ?? []).map(\.id) })
        guard Set(reviewFlags.keys).isSubset(of: sourceItemIDs) else { return nil }
        for source in lesson.blocks {
            guard let copy = byID[source.id],
                  copy.sourceTitle == source.title,
                  copy.sourceInstructions == source.instructions,
                  !copy.titleFR.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !copy.instructionsFR.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Self.quantities(copy.sourceTitle) == Self.quantities(copy.titleFR),
                  Self.quantities(copy.sourceInstructions) == Self.quantities(copy.instructionsFR) else { return nil }
            let items = source.sourceItems ?? []
            guard copy.sourceItems.count == items.count,
                  Set(copy.sourceItems.map(\.itemID)).count == items.count else { return nil }
            let localizedItems = Dictionary(uniqueKeysWithValues: copy.sourceItems.map { ($0.itemID, $0) })
            for item in items {
                guard let localized = localizedItems[item.id], localized.sourceText == item.text,
                      !localized.textFR.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      Self.quantities(localized.sourceText) == Self.quantities(localized.textFR) else { return nil }
            }
        }
        return byID
    }
}

extension SessionBlock {
    func displaySourceTitle(language: String) -> String? {
        language == "fr" ? localizedSourceTitleFR ?? sourceTitle : sourceTitle
    }
    func displaySourceInstructions(language: String) -> String? {
        language == "fr" ? localizedSourceInstructionsFR ?? sourceInstructions : sourceInstructions
    }
    func sourceSpeechLanguage(displayLanguage: String) -> String {
        displayLanguage == "fr" && localizedSourceTitleFR != nil ? "fr" : "en"
    }
}
