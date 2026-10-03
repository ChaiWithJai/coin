import Foundation

/// A checked-in snapshot of the workout source. Importing a prescription never
/// turns it into evidence that the boxer performed the exercise.
struct WorkoutCatalog: Decodable {
    let schemaVersion: Int
    let workouts: [WorkoutLesson]
    var lessons: [WorkoutLesson] { workouts }
    var error: String? = nil

    enum CodingKeys: String, CodingKey { case schemaVersion, workouts }

    static let shared: WorkoutCatalog = {
        guard let url = Bundle.main.url(forResource: "WorkoutCatalog", withExtension: "json") else {
            return WorkoutCatalog(schemaVersion: 1, workouts: [], error: "WorkoutCatalog.json is missing.")
        }
        do { return try load(Data(contentsOf: url)) }
        catch { return WorkoutCatalog(schemaVersion: 1, workouts: [], error: error.localizedDescription) }
    }()

    static func load(_ data: Data) throws -> WorkoutCatalog {
        let catalog = try JSONDecoder().decode(WorkoutCatalog.self, from: data)
        guard catalog.schemaVersion == 1,
              Set(catalog.workouts.map(\.id)).count == catalog.workouts.count else {
            throw CatalogError.invalid("Unsupported catalog version or duplicate workout identifiers.")
        }
        for lesson in catalog.workouts {
            guard !lesson.id.isEmpty, !lesson.title.isEmpty, !lesson.blocks.isEmpty,
                  URL(string: lesson.sourceURL)?.scheme == "https" else {
                throw CatalogError.invalid("Incomplete source workout: \(lesson.id)")
            }
            for block in lesson.blocks {
                guard !block.title.isEmpty, !block.instructions.isEmpty,
                      (1...100).contains(block.rounds ?? 1),
                      (0...3600).contains(block.restSeconds ?? 0),
                      block.completion != .timed || (1...7200).contains(block.durationSeconds ?? 0) else {
                    throw CatalogError.invalid("Invalid block in \(lesson.id): \(block.id)")
                }
            }
        }
        return catalog
    }

    enum CatalogError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }
}

struct WorkoutLesson: Decodable, Identifiable {
    let id: String
    let program: String
    let week: Int
    let day: Int
    let title: String
    let focus: String?
    let sourceURL: String
    let sourcePDFURL: String?
    let sourceSHA256: String
    let blocks: [WorkoutSourceBlock]
    var programID: String { program }

    func template() -> TrainingTemplate {
        var roundNumber = 0
        var sessionBlocks = blocks.flatMap { source -> [SessionBlock] in
            if let steps = source.manualSteps {
                return steps.map { step in
                    SessionBlock(kind: .exercise, minutes: 0, roundNumber: nil, drillID: source.drillID, restAfterMinutes: 0,
                                 durationSeconds: 0, restAfterSeconds: 0,
                                 sourceTitle: step.item.text, sourceInstructions: step.instructions,
                                 sourceURL: source.sourceURL ?? sourceURL, sourceDemoURLs: step.item.demoURLs,
                                 sourceActivityKey: source.reviewedActivityKey(for: step.item),
                                 sourceBlockID: source.id, sourceItemID: step.item.id,
                                 repetitionText: step.prescription, completionMode: .manual)
                }
            }
            let count = source.completion == .timed ? (source.rounds ?? 1) : 1
            let roundItems = source.reviewedPadRoundItems
            return (0..<count).map { repetition in
                let roundItem = roundItems?[repetition]
                if source.kind == .boxing { roundNumber += 1 }
                // Rest belongs between repetitions. Do not invent a final rest
                // before the next source section, or a duration for rep work.
                let seconds = source.completion == .timed ? (source.durationSeconds ?? 0) : 0
                let rest = repetition < count - 1 ? (source.restSeconds ?? 0) : 0
                let prescription = [source.sets.map { "\($0) sets" }, source.reps]
                    .compactMap { $0 }.joined(separator: " · ")
                return SessionBlock(kind: source.kind ?? .exercise, minutes: seconds / 60,
                                    roundNumber: source.kind == .boxing ? roundNumber : nil,
                                    drillID: source.drillID, restAfterMinutes: rest / 60,
                                    durationSeconds: seconds, restAfterSeconds: rest,
                                    sourceTitle: roundItem?.text ?? source.title,
                                    sourceInstructions: roundItem.map { source.title + "\n" + $0.text } ?? source.instructions,
                                    sourceURL: source.sourceURL ?? sourceURL,
                                    sourceDemoURLs: roundItem.map { source.padRoundDemoURLs(for: $0) } ?? source.demoURLs,
                                    sourceActivityKey: source.reviewedWholeBlockActivityKey,
                                    sourceBlockID: source.id,
                                    sourceItemID: roundItem?.id ?? source.reviewedWholeBlockItemID,
                                    repetitionText: prescription.isEmpty ? nil : prescription,
                                    completionMode: source.completion,
                                    activityChoiceFamily: source.reviewedChoiceFamily)
            }
        }
        var localizedTitleFR: String?
        if let overlay = SourceWorkoutFrenchOverlay.bundled(for: id),
           let localizedBlocks = overlay.localizedBlocks(for: self, blocks: sessionBlocks) {
            localizedTitleFR = overlay.sourceTitleFR
            sessionBlocks = localizedBlocks
        }
        let seconds = sessionBlocks.reduce(0) { $0 + $1.effectiveSeconds + $1.effectiveRestSeconds }
        return TrainingTemplate(id: id, durationMinutes: Int(ceil(Double(seconds) / 60)),
                                blocks: sessionBlocks, sourceTitle: title,
                                localizedSourceTitleFR: localizedTitleFR,
                                sourceURL: sourceURL, sourceVersion: sourceSHA256)
    }
}

struct WorkoutSourceBlock: Decodable, Identifiable {
    let id: String
    let title: String
    let instructions: String
    let kind: SessionBlockKind?
    let drillID: String?
    let activityKey: String?
    let rounds: Int?
    let durationSeconds: Int?
    let restSeconds: Int?
    let reps: String?
    let sets: Int?
    let completion: BlockCompletionMode
    let demoURLs: [String]?
    let sourceText: String?
    let sourceSectionIndex: Int?
    let sourceURL: String?
    let sourceItems: [WorkoutSourceItem]?
}

struct WorkoutSourceItem: Decodable {
    let id: String
    let text: String
    let demoURLs: [String]?
}

extension WorkoutSourceBlock {
    var reviewedWholeBlockItemID: String? {
        activityKey == nil && reviewedWholeBlockActivityKey == "squat_jumps" ? sourceItems?.first?.id : nil
    }

    /// A complete one-line source prescription can identify the movement without
    /// implying that a repetition was seen. This mapping is tied to exact items;
    /// mixed conditioning sections must remain unassigned.
    var reviewedWholeBlockActivityKey: String? {
        if let activityKey { return activityKey }
        let stanceOnly: [String: (title: String, instructions: String)] = [
            "basic-w1-d1-p3-s3-1": ("FR0NTAL STANCE DRILL",
                "FR0NTAL STANCE DRILL\n4 ROUNDS OF 2 MINUTES WITH 30 SECONDS OF REST IN BETWEEN."),
            "basic-w1-d1-p3-s5-1": ("FRONTAL STANCE MOVEMENT DRILL",
                "FRONTAL STANCE MOVEMENT DRILL\n(JUST GO IN ALL DIERECTIONS). 1 ROUND OF 2 MINUTES"),
            "basic-w1-d1-p3-s7-1": ("FRONTAL STANCE DEFENSIVE DRILL",
                "FRONTAL STANCE DEFENSIVE DRILL\n(SLIP, SLIP MOVE, ROLL ROLL). 1 ROUND OF 2 MINUTES"),
        ]
        if let match = stanceOnly[id], kind == .boxing, completion == .timed,
           title == match.title, instructions == match.instructions,
           sourceText == match.instructions { return "frontal_stance" }
        let exact: [String: (item: String, text: String)] = [
            "basic-w1-d1-p3-s6-2": ("p3-b18", "12 JUMP SQUATS"),
            "basic-w2-d1-p10-s5-2": ("p10-b15", "12 JUMP SQUATS"),
            "basic-w2-d5-p14-s3-2": ("p14-b7", "10 JUMP SQUATS"),
            "basic-w3-d1-p17-s5-2": ("p17-b17", "12 JUMP SQUATS"),
            "basic-w3-d5-p21-s3-2": ("p21-b6", "10 JUMP SQUATS"),
            "basic-w4-d1-p24-s5-2": ("p24-b17", "12 JUMP SQUATS"),
            "basic-w4-d5-p28-s3-2": ("p28-b6", "10 JUMP SQUATS"),
            "basic-w5-d1-p31-s5-2": ("p31-b17", "12 JUMP SQUATS"),
        ]
        guard let match = exact[id], completion == .manual,
              title == match.text, instructions == match.text,
              sourceText == match.text,
              sourceItems?.count == 1,
              sourceItems?.first?.id == match.item,
              sourceItems?.first?.text == match.text else { return nil }
        return "squat_jumps"
    }

    /// These source sections name a conditioning slot but no movement. Runtime
    /// choice is product metadata, not an edit to the source prescription.
    var reviewedChoiceFamily: String? {
        let genericConditioning: Set<String> = [
            "basic-w2-d1-p10-s7-2", "basic-w2-d5-p14-s6-2",
            "basic-w3-d1-p17-s7-2", "basic-w3-d5-p21-s6-2",
            "basic-w4-d1-p24-s7-2",
        ]
        guard genericConditioning.contains(id), title.hasPrefix("CONDITIONING DRILL"),
              instructions == title else { return nil }
        return "conditioning"
    }

    /// An exact item can select a candidate counter; a word inside a mixed
    /// section cannot. These four IDs were reviewed against the source snapshot.
    func reviewedActivityKey(for item: WorkoutSourceItem) -> String? {
        let exact: [String: (itemID: String, text: String, key: String)] = [
            "basic-w1-d6-p8-s1-1": ("p8-b6", "Squat", "squats"),
            "competitive-w1-d2-p6-s8-1": ("p6-b50", "Long Step Lunge", "lunges"),
            "competitive-w3-d2-p22-s8-1": ("p22-b38", "Reverse Lunges", "lunges"),
            "competitive-w4-d2-p30-s9-1": ("p30-b53", "Long Step Lunge", "lunges"),
        ]
        guard let match = exact[id], match.itemID == item.id, match.text == item.text else { return nil }
        return match.key
    }

    /// These five source lists were checked for one complete instruction per
    /// round. Cardinality alone is unsafe: other lists contain wrapped sentences.
    /// A changed snapshot must be reviewed again before receiving this mapping.
    static let reviewedPadRounds: [String: (page: Int, headingIndex: Int, focus: [String])] = [
        "competitive-w1-d4-p8-s4-1": (8, 17, [
            "SINGLE PUNCHES", "DOUBLED-UP PUNCHES", "2 PUNCH COMBOS", "3 PUNCH COMBOS", "ATTACK - DEFEND - ATTACK"
        ]),
        "competitive-w2-d4-p16-s4-1": (16, 12, [
            "HEAD MOVEMENT COUNTERS", "FOOTWORK COUNTERS", "HANDS DEFENSE COUNTERS", "SIMULTANIOUS COUNTERS", "PROVOCATION COUNTERS"
        ]),
        "competitive-w3-d4-p24-s4-1": (24, 14, [
            "SETTING TRAPS WITH THE JAB", "SETTING TRAPS WITH THE CROSS", "SETTING TRAPS WITH YOUR RHYTHM", "SETTING TRAPS AT THE CLOSE RANGE", "SETTING UP BODY SHOTS"
        ]),
        "competitive-w4-d4-p32-s4-1": (32, 13, [
            "COMBOS EMPHASISING THE CROSS", "COMBOS EMPHASISING THE HOOKS", "COMBOS EMPHASISING THE UPPERCUTS", "COMBOS EMPHASISING THE BODY SHOTS", "COMBOS EMPHASISING ANY POWER PUNCH"
        ]),
        "competitive-w5-d4-p40-s4-1": (40, 13, [
            "SINGLE PUNCHES", "DOUBLE UP ATTACKS", "2 PUNCH COMBOS", "3 COMBOS AFTER A DEFENSIVE MOVE", "PROVACATION - DEFENCE - COMBO"
        ]),
    ]

    var reviewedPadRoundItems: [WorkoutSourceItem]? {
        guard let snapshot = Self.reviewedPadRounds[id], completion == .timed,
              kind == .boxing, rounds == 5, durationSeconds == 180,
              title == "VIRTUAL PAD WORK (5 ROUNDS OF 3 MINUTES)",
              let items = sourceItems, items.count == 6,
              items.map(\.text) == [title] + snapshot.focus,
              items.map(\.id) == (0..<6).map({ "p\(snapshot.page)-b\(snapshot.headingIndex + $0)" }),
              items.map(\.text).joined(separator: "\n") == instructions,
              sourceText == instructions else { return nil }
        return Array(items.dropFirst())
    }

    func padRoundDemoURLs(for item: WorkoutSourceItem) -> [String] {
        // The heading video is shared section context, not an exact round clip.
        var seen = Set<String>()
        return ((sourceItems?.first?.demoURLs ?? []) + (item.demoURLs ?? []))
            .filter { seen.insert($0).inserted }
    }

    struct ManualStep {
        let item: WorkoutSourceItem
        let prescription: String
        let instructions: String
    }

    /// Interpret only complete, explicit lists. Unknown lines retain the original
    /// manual section rather than guessing an exercise, grouping, or duration.
    var manualSteps: [ManualStep]? {
        guard completion == .manual, let items = sourceItems, items.count > 1,
              items.allSatisfy({ !$0.id.isEmpty && !$0.text.isEmpty }),
              Set(items.map(\.id)).count == items.count,
              items.map(\.text).joined(separator: "\n") == instructions else { return nil }
        let comboHeading = "SHADOW BOXING: PRACTICE 5 TIMES EACH OF THE 12 COMBOS"
        if items.first?.text == comboHeading {
            guard items.count == 13, items.dropFirst().allSatisfy({ item in
                !(item.demoURLs ?? []).isEmpty && !item.text.contains("\n")
            }) else { return nil }
            return items.dropFirst().map {
                ManualStep(item: $0, prescription: comboHeading,
                           instructions: comboHeading + "\n" + $0.text)
            }
        }

        var preamble: [String] = []
        var prescription: String?
        var groupCount = 0
        var steps: [ManualStep] = []
        for item in items {
            if matches("^[1-9][0-9]* SETS OF [1-9][0-9]*(?:-[1-9][0-9]*)? REPS EACH EXERCISE$", item.text) {
                if prescription != nil && groupCount == 0 { return nil }
                prescription = item.text
                groupCount = 0
            } else if let prescription {
                guard !(item.demoURLs ?? []).isEmpty, item.text.count <= 80,
                      !matches("[;:\\n.]|\\b(SETS?|REPS?|ROUNDS?|REST|MINUTES?|SECONDS?)\\b", item.text.uppercased()) else { return nil }
                steps.append(ManualStep(item: item, prescription: prescription,
                                        instructions: (preamble + [prescription, item.text]).joined(separator: "\n")))
                groupCount += 1
            } else {
                guard item.text == "WARM UP:" || matches("^LIFT #[1-9][0-9]* WARM UP:$", item.text) else { return nil }
                preamble.append(item.text)
            }
        }
        guard groupCount > 0, steps.count > 1 else { return nil }
        return steps
    }

    func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
