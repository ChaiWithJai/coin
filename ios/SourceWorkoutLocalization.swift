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

    /// Resolve every expanded runtime line against its pinned source item. A
    /// single unmappable line rejects the entire day, so a session never mixes
    /// French headings with English exercise instructions.
    func localizedBlocks(for lesson: WorkoutLesson, blocks: [SessionBlock]) -> [SessionBlock]? {
        guard let copyByID = validated(for: lesson) else { return nil }
        let sourceByID = Dictionary(uniqueKeysWithValues: lesson.blocks.map { ($0.id, $0) })
        var result: [SessionBlock] = []
        for block in blocks {
            guard let sourceID = block.sourceBlockID,
                  let source = sourceByID[sourceID],
                  let copy = copyByID[sourceID],
                  let localized = localizedText(for: block, source: source, copy: copy) else { return nil }
            var translated = block
            translated.localizedSourceTitleFR = localized.title
            translated.localizedSourceInstructionsFR = localized.instructions
            result.append(translated)
        }
        return result
    }

    private func localizedText(for block: SessionBlock, source: WorkoutSourceBlock,
                               copy: Block) -> (title: String, instructions: String)? {
        if block.sourceTitle == source.title && block.sourceInstructions == source.instructions {
            return (copy.titleFR, copy.instructionsFR)
        }
        let byID = Dictionary(uniqueKeysWithValues: copy.sourceItems.map { ($0.itemID, $0) })
        if let steps = source.manualSteps,
           let itemID = block.sourceItemID,
           let step = steps.first(where: { $0.item.id == itemID }),
           block.sourceTitle == step.item.text,
           block.sourceInstructions == step.instructions,
           let itemCopy = byID[itemID] {
            // Each generated line must be one complete source item. Repeated
            // identical source lines may resolve only to identical translations.
            var byText: [String: String] = [:]
            for item in source.sourceItems ?? [] {
                guard let translated = byID[item.id]?.textFR else { return nil }
                if let previous = byText[item.text], previous != translated { return nil }
                byText[item.text] = translated
            }
            let lines = step.instructions.components(separatedBy: "\n")
            let translatedLines = lines.map { byText[$0] }
            guard translatedLines.allSatisfy({ $0 != nil }) else { return nil }
            return (itemCopy.textFR, translatedLines.compactMap { $0 }.joined(separator: "\n"))
        }
        if let roundItems = source.reviewedPadRoundItems,
           let itemID = block.sourceItemID,
           let item = roundItems.first(where: { $0.id == itemID }),
           block.sourceTitle == item.text,
           block.sourceInstructions == source.title + "\n" + item.text,
           let itemCopy = byID[itemID] {
            return (itemCopy.textFR, copy.titleFR + "\n" + itemCopy.textFR)
        }
        return nil
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
