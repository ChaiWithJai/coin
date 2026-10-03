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

    /// Builds the immutable source-derived plan. Runtime overlay validation uses
    /// this path too, avoiding recursion through the bundled overlay bridge.
    func sourceTemplate() -> TrainingTemplate {
        var roundNumber = 0
        var sessionBlocks = blocks.flatMap { source -> [SessionBlock] in
            if let steps = source.reviewedMixedDaySteps {
                return steps.map { step in
                    if step.kind == .boxing { roundNumber += 1 }
                    return SessionBlock(kind: step.kind, minutes: step.durationSeconds / 60,
                        roundNumber: step.kind == .boxing ? roundNumber : nil,
                        drillID: nil, restAfterMinutes: step.restSeconds / 60,
                        durationSeconds: step.durationSeconds, restAfterSeconds: step.restSeconds,
                        sourceTitle: step.title, sourceInstructions: step.instructions,
                        sourceURL: source.sourceURL ?? sourceURL, sourceDemoURLs: step.demoURLs,
                        sourceBlockID: source.id, sourceItemID: step.sourceItemID,
                        repetitionText: step.prescription, completionMode: step.completion)
                }
            }
            if let intervals = source.reviewedBagExerciseIntervals {
                return intervals.flatMap { interval -> [SessionBlock] in
                    roundNumber += 1
                    let round = SessionBlock(kind: .boxing, minutes: 2, roundNumber: roundNumber,
                        drillID: source.drillID, restAfterMinutes: 0,
                        durationSeconds: 120, restAfterSeconds: 0,
                        sourceTitle: interval.focusText,
                        sourceInstructions: source.title + "\n" + interval.focusText,
                        sourceURL: source.sourceURL ?? sourceURL,
                        sourceDemoURLs: source.roundSequenceDemoURLs(for: interval.sourceItemIDs),
                        sourceActivityKey: "bag_work", sourceBlockID: source.id,
                        sourceItemID: interval.sourceItemIDs.first, completionMode: .timed)
                    guard interval.hasExerciseInterstitial else { return [round] }
                    let exercise = SessionBlock(kind: .exercise, minutes: 0, roundNumber: nil,
                        drillID: nil, restAfterMinutes: 0, durationSeconds: 0, restAfterSeconds: 0,
                        sourceTitle: interval.exerciseText, sourceInstructions: interval.exerciseText,
                        sourceURL: source.sourceURL ?? sourceURL,
                        sourceDemoURLs: source.roundSequenceDemoURLs(for: [interval.exerciseItemID]),
                        sourceBlockID: source.id, sourceItemID: interval.exerciseItemID,
                        repetitionText: "10 push-ups + 10 squats", completionMode: .manual)
                    return [round, exercise]
                }
            }
            if let sequence = source.reviewedRoundSequence {
                return sequence.map { step in
                    if source.kind == .boxing { roundNumber += 1 }
                    return SessionBlock(kind: source.kind ?? .exercise, minutes: step.durationSeconds / 60,
                                 roundNumber: source.kind == .boxing ? roundNumber : nil,
                                 drillID: source.drillID, restAfterMinutes: step.restSeconds / 60,
                                 durationSeconds: step.durationSeconds, restAfterSeconds: step.restSeconds,
                                 sourceTitle: step.focusText, sourceInstructions: source.title + "\n" + step.focusText,
                                 sourceURL: source.sourceURL ?? sourceURL,
                                 sourceDemoURLs: source.roundSequenceDemoURLs(for: step.sourceItemIDs),
                                 sourceBlockID: source.id, sourceItemID: step.sourceItemIDs.first,
                                 completionMode: .timed)
                }
            }
            if let steps = source.reviewedLinkedRunSteps {
                let linkedItemID = source.sourceItems?.first {
                    ($0.referenceURLs ?? []).contains { $0.contains("docs.google.com/document/d/") }
                }?.id
                return steps.map { step in
                    if step.kind == .boxing { roundNumber += 1 }
                    return SessionBlock(kind: step.kind, minutes: step.durationSeconds / 60,
                        roundNumber: step.kind == .boxing ? roundNumber : nil,
                        drillID: step.drillID, restAfterMinutes: step.restSeconds / 60,
                        durationSeconds: step.durationSeconds, restAfterSeconds: step.restSeconds,
                        sourceTitle: step.title, sourceInstructions: step.instructions,
                        sourceURL: step.sourceURL, sourceDemoURLs: source.demoURLs ?? [],
                        sourceActivityKey: step.activityKey, sourceBlockID: source.id,
                        sourceItemID: linkedItemID, repetitionText: step.prescription,
                        completionMode: step.completion)
                }
            }
            if let steps = source.reviewedEnduranceCircuitSteps {
                return steps.map { step in
                    SessionBlock(kind: .exercise, minutes: 1, roundNumber: nil, drillID: nil,
                                 restAfterMinutes: step.restSeconds / 60,
                                 durationSeconds: 60, restAfterSeconds: step.restSeconds,
                                 sourceTitle: step.item.text, sourceInstructions: source.instructions,
                                 sourceURL: source.sourceURL ?? sourceURL, sourceDemoURLs: source.demoURLs,
                                 sourceBlockID: source.id, sourceItemID: step.item.id,
                                 repetitionText: "Circuit \(step.circuit) of 3",
                                 completionMode: .timed)
                }
            }
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

    func template() -> TrainingTemplate {
        let source = sourceTemplate()
        guard let overlay = ReviewedRuntimeDrillOverlay.bundled(for: id, catalog: .shared),
              let blocks = overlay.applying(to: self, blocks: source.blocks) else { return source }
        return TrainingTemplate(id: source.id, durationMinutes: source.durationMinutes, blocks: blocks,
            sourceTitle: source.sourceTitle, localizedSourceTitleFR: source.localizedSourceTitleFR,
            sourceURL: source.sourceURL, sourceVersion: source.sourceVersion)
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
    let referenceURLs: [String]?
    let sourceItems: [WorkoutSourceItem]?
}

struct WorkoutSourceItem: Decodable {
    let id: String
    let text: String
    let demoURLs: [String]?
    let referenceURLs: [String]?
}

extension WorkoutSourceBlock {
    struct ReviewedMixedDayStep {
        let sourceItemID: String
        let title: String
        let instructions: String
        let demoURLs: [String]
        let kind: SessionBlockKind
        let durationSeconds: Int
        let restSeconds: Int
        let prescription: String?
        let completion: BlockCompletionMode
    }

    /// This source section combines several independent prescriptions. Expand
    /// only the reviewed snapshot, preserving each source item's wording and
    /// links. In particular, the dumbbell line has no duration and stays manual.
    var reviewedMixedDaySteps: [ReviewedMixedDayStep]? {
        guard id == "basic-w1-d3-p5-s6-1", completion == .manual, kind == .exercise,
              drillID == nil, activityKey == nil, rounds == nil, durationSeconds == nil,
              restSeconds == nil, sets == 1, reps == nil,
              title == "7 ROUNDS OF 3 MINUTES WITH 1 MINUTE OF REST IN",
              let items = sourceItems,
              items.map(\.id) == ["p5-b22", "p5-b24", "p5-b27", "p5-b29", "p5-b31", "p5-b32",
                  "p5-b34", "p5-b36", "p5-b38", "p5-b40", "p5-b41", "p5-b43", "p5-b45", "p5-b47"],
              items.map(\.text) == [
                  "7 ROUNDS OF 3 MINUTES WITH 1 MINUTE OF REST IN", "BETWEEN OF BAG WORK",
                  "1 AND 2 COMBOS", "7 AND 8 COMBOS", "3 AND 4 COMBOS", "9 AND 10 COMBOS",
                  "5 AND 6 COMBOS", "11 AND 12 COMBOS",
                  "VOICE CONTROLED BOXING. I SAY COMBO - YOU THROW IT", "(ROUND 1 OF THE LINKED VIDEO)",
                  "Practice punches with a tennis ball. 3 rounds of 1 minute",
                  "Shadow boxing with dumbbells",
                  "1 set of max: parallel bar dips, pull-ups, jumping squat lunges and hanging leg raises.",
                  "Rest for 1 minute between exercises.",
              ],
              items.map(\.text).joined(separator: "\n") == instructions,
              sourceText == instructions,
              items[8].demoURLs == ["https://youtu.be/oYG9JVu3k38?si=e81bxKdTvx3vyWoD&t=17"],
              items[10].demoURLs == ["https://www.youtube.com/shorts/-QbhRExILuw"],
              items[11].demoURLs == ["https://www.youtube.com/shorts/-NkpM5DYF2Y"],
              items[12].demoURLs == [
                  "https://www.youtube.com/shorts/vK-XgduCGS8",
                  "https://www.youtube.com/shorts/ZPG8OsHKXLw",
                  "https://www.youtube.com/watch?v=IlVleQhEANA&ab_channel=EPICIntervalTraining",
                  "https://www.youtube.com/shorts/7DoFMV1Dnow",
              ] else { return nil }

        let bagHeading = items[0].text + "\n" + items[1].text
        var steps = items[2...7].map { item in
            ReviewedMixedDayStep(sourceItemID: item.id, title: item.text,
                instructions: bagHeading + "\n" + item.text, demoURLs: item.demoURLs ?? [],
                kind: .boxing, durationSeconds: 180, restSeconds: 60,
                prescription: nil, completion: .timed)
        }
        steps.append(ReviewedMixedDayStep(sourceItemID: items[8].id, title: items[8].text,
            instructions: bagHeading + "\n" + items[8].text + "\n" + items[9].text,
            demoURLs: items[8].demoURLs ?? [], kind: .boxing, durationSeconds: 180,
            restSeconds: 0, prescription: nil, completion: .timed))
        for _ in 0..<3 {
            steps.append(ReviewedMixedDayStep(sourceItemID: items[10].id, title: items[10].text,
                instructions: items[10].text, demoURLs: items[10].demoURLs ?? [], kind: .boxing,
                durationSeconds: 60, restSeconds: 0, prescription: nil, completion: .timed))
        }
        steps.append(ReviewedMixedDayStep(sourceItemID: items[11].id, title: items[11].text,
            instructions: items[11].text, demoURLs: items[11].demoURLs ?? [], kind: .boxing,
            durationSeconds: 0, restSeconds: 0, prescription: nil, completion: .manual))
        let strengthNames = ["parallel bar dips", "pull-ups", "jumping squat lunges", "hanging leg raises"]
        for (index, name) in strengthNames.enumerated() {
            steps.append(ReviewedMixedDayStep(sourceItemID: items[12].id, title: name,
                instructions: items[12].text, demoURLs: [items[12].demoURLs![index]], kind: .exercise,
                durationSeconds: 0, restSeconds: index < strengthNames.count - 1 ? 60 : 0,
                prescription: "1 set of max", completion: .manual))
        }
        return steps
    }

    struct ReviewedBagExerciseInterval {
        let sourceItemIDs: [String]
        let focusText: String
        let exerciseItemID: String
        let exerciseText: String
        let hasExerciseInterstitial: Bool
    }

    /// This source prescribes ten two-minute bag rounds and exercises "during
    /// rest periods", but gives no rest duration. Keep the bag clocks exact and
    /// expose the exercises as manual interstitials between rounds only.
    var reviewedBagExerciseIntervals: [ReviewedBagExerciseInterval]? {
        guard id == "competitive-w4-d3-p31-s4-1", completion == .manual,
              kind == .exercise, drillID == nil, activityKey == nil,
              rounds == nil, durationSeconds == nil, restSeconds == nil,
              title == "BAG WORK (10 ROUNDS OF 2 MINUTES)",
              let items = sourceItems,
              items.map(\.id) == ["p31-b15", "p31-b16", "p31-b17", "p31-b18", "p31-b19",
                                  "p31-b20", "p31-b21", "p31-b22", "p31-b24", "p31-b25",
                                  "p31-b27", "p31-b29", "p31-b31"],
              items.map(\.text) == [
                "BAG WORK (10 ROUNDS OF 2 MINUTES)",
                "(add 10 push-ups and 10 squats during rest periods)",
                "JAB BODY — FAKE JAB - OVERHAND",
                "JAB — LONG LEAD UPPERCUT - CROSS",
                "JAB-CROSS — JAB-FEINT CROSS-HOOK",
                "JAB-JAB-CROSS — SPINNING JAB-JAB-REAR HOOK",
                "JAB — FOOT AND HAND FEINT - JAB-CROSS",
                "JAB — STOP WITH THE HIGHT GUARD — PULL BACK COUNTER",
                "HOOK BODY - HOOK BODY - HOOK HEAD — HOOK BODY -HOOK BODY - UPPERCUT",
                "HEAD",
                "JAB - SLIP - LONG LEAD UPPERCUT — JAB - STEP IN SLIP - LIVER HOOK - OVERHAND",
                "JAB-CROSS-LIVER HOOK — JAB-CROSS-NARROW SOLAR PLEXUS UPPERCUT",
                "FREESTYLE USING THE SET UPS",
              ],
              items.map(\.text).joined(separator: "\n") == instructions,
              sourceText == instructions else { return nil }
        let exercise = items[1]
        let focuses: [([String], String)] = [
            (["p31-b17"], items[2].text), (["p31-b18"], items[3].text),
            (["p31-b19"], items[4].text), (["p31-b20"], items[5].text),
            (["p31-b21"], items[6].text), (["p31-b22"], items[7].text),
            (["p31-b24", "p31-b25"], items[8].text + "\n" + items[9].text),
            (["p31-b27"], items[10].text), (["p31-b29"], items[11].text),
            (["p31-b31"], items[12].text),
        ]
        return focuses.enumerated().map { index, focus in
            ReviewedBagExerciseInterval(sourceItemIDs: focus.0, focusText: focus.1,
                exerciseItemID: exercise.id, exerciseText: exercise.text,
                hasExerciseInterstitial: index < focuses.count - 1)
        }
    }

    struct ReviewedRoundStep {
        let sourceItemIDs: [String]
        let focusText: String
        let durationSeconds: Int
        let restSeconds: Int
    }

    /// Exact source-pinned schedules that the conservative importer leaves
    /// manual because their timing is spread across several source items or a
    /// source typo says "RUNDS". Changed snapshots fall back to one untouched
    /// manual block rather than receiving an inferred clock.
    var reviewedRoundSequence: [ReviewedRoundStep]? {
        struct Snapshot {
            let items: [(String, String)]
            let focuses: [([String], String)]
            let durationSeconds: Int
            let restSeconds: Int
        }
        let snapshots: [String: Snapshot] = [
            "competitive-w5-d1-p37-s3-1": Snapshot(items: [
                ("p37-b5", "SHADOW BOXING"),
                ("p37-b6", "GO FOR 3 ROUNDS OF 3 MINUTES WITH 1 MINUTE OF REST IN BETWEEN OF"),
                ("p37-b7", "LIMITED FREESTYLE SHADOW BOXING:"),
                ("p37-b8", "USE ONLY THE LEAD HAND. 1ROUND OF 3MINUTES"),
                ("p37-b9", "USE ONLY THE REAR HAND. 1ROUND OF 3MINUTES"),
                ("p37-b10", "FREESTYLE WORK WITH FOCUS ON COMBOS. 1ROUND OF 3MINUTES"),
            ], focuses: [
                (["p37-b8"], "USE ONLY THE LEAD HAND. 1ROUND OF 3MINUTES"),
                (["p37-b9"], "USE ONLY THE REAR HAND. 1ROUND OF 3MINUTES"),
                (["p37-b10"], "FREESTYLE WORK WITH FOCUS ON COMBOS. 1ROUND OF 3MINUTES"),
            ], durationSeconds: 180, restSeconds: 60),
            "competitive-w5-d2-p38-s5-1": Snapshot(items: [
                ("p38-b18", "VESTIBULAR APPARATUS TRAINING"),
                ("p38-b19", "spin left + shadow box. 1 round of 1 minute with 30 seconds of rest"),
                ("p38-b20", "spin right + shadow box. 1 round of 1 minute with 30 seconds of rest"),
                ("p38-b21", "roll + shadow box. 1 round of 1 minute with 30 seconds of rest"),
            ], focuses: [
                (["p38-b19"], "spin left + shadow box. 1 round of 1 minute with 30 seconds of rest"),
                (["p38-b20"], "spin right + shadow box. 1 round of 1 minute with 30 seconds of rest"),
                (["p38-b21"], "roll + shadow box. 1 round of 1 minute with 30 seconds of rest"),
            ], durationSeconds: 60, restSeconds: 30),
            "basic-w2-d2-p11-s8-1": Snapshot(items: [
                ("p11-b24", "VIRTUAL PAD WORK. 5 RUNDS OF 3 MINUTES"),
                ("p11-b25", "SINGLE SIMULTANIOUS COUNTERS IN FRONTAL STANCE"),
                ("p11-b27", "DEFENSIVE MOVE + 2 PUNCHES IN FONTAL STANCE"),
                ("p11-b29", "SINGLE SIMULTANIOUS COUNTERS IN FIGHTING STANCE"),
                ("p11-b30", "DEFENSIVE MOVE + 2 PUNCHES IN FIGHTING STANCE"),
                ("p11-b32", "SINGLE PUNCHES IN FIGHTING STANCE WITH STEPS BACK"),
            ], focuses: [
                (["p11-b25"], "SINGLE SIMULTANIOUS COUNTERS IN FRONTAL STANCE"),
                (["p11-b27"], "DEFENSIVE MOVE + 2 PUNCHES IN FONTAL STANCE"),
                (["p11-b29"], "SINGLE SIMULTANIOUS COUNTERS IN FIGHTING STANCE"),
                (["p11-b30"], "DEFENSIVE MOVE + 2 PUNCHES IN FIGHTING STANCE"),
                (["p11-b32"], "SINGLE PUNCHES IN FIGHTING STANCE WITH STEPS BACK"),
            ], durationSeconds: 180, restSeconds: 0),
            "basic-w3-d2-p18-s8-1": Snapshot(items: [
                ("p18-b25", "VIRTUAL PAD WORK. 5 RUNDS OF 3 MINUTES"),
                ("p18-b26", "SLIP + PIVOT + 1 PUNCH"),
                ("p18-b27", "DEFENSIVE MOVE + PIVOT + 1 PUNCH IN FIGHTING STANCE"),
                ("p18-b28", "DEFENSIVE MOVE + PIVOT + 2 PUNCHES IN FIGHTING STANCE"),
                ("p18-b30", "JAB + ANY DEFENCE + 2 PUNCHES"),
                ("p18-b31", "JAB + ANY DEFENCE + PIVOT + 2 PUNCHES"),
            ], focuses: [
                (["p18-b26"], "SLIP + PIVOT + 1 PUNCH"),
                (["p18-b27"], "DEFENSIVE MOVE + PIVOT + 1 PUNCH IN FIGHTING STANCE"),
                (["p18-b28"], "DEFENSIVE MOVE + PIVOT + 2 PUNCHES IN FIGHTING STANCE"),
                (["p18-b30"], "JAB + ANY DEFENCE + 2 PUNCHES"),
                (["p18-b31"], "JAB + ANY DEFENCE + PIVOT + 2 PUNCHES"),
            ], durationSeconds: 180, restSeconds: 0),
            "basic-w4-d2-p25-s7-1": Snapshot(items: [
                ("p25-b21", "VIRTUAL PAD WORK. 5 RUNDS OF 3 MINUTES"),
                ("p25-b22", "PUNCH-SLIP OUTSIDE-PUNCH-SLIP INSIDE IN FRONTAL"),
                ("p25-b23", "STANCE"),
                ("p25-b24", "SLIP + SHIFT + 1 PUNCH IN FONTAL STANCE"),
                ("p25-b25", "PUNCH-SLIP OUTSIDE-PUNCH-SLIP INSIDE IN FRONTAL"),
                ("p25-b26", "STANCE"),
                ("p25-b27", "SLIP + SHIFT + 1 OR 2 PUNCHES STANCE"),
                ("p25-b28", "JAB + ANY DEFENCE + 2 PUNCHES"),
            ], focuses: [
                (["p25-b22", "p25-b23"], "PUNCH-SLIP OUTSIDE-PUNCH-SLIP INSIDE IN FRONTAL\nSTANCE"),
                (["p25-b24"], "SLIP + SHIFT + 1 PUNCH IN FONTAL STANCE"),
                (["p25-b25", "p25-b26"], "PUNCH-SLIP OUTSIDE-PUNCH-SLIP INSIDE IN FRONTAL\nSTANCE"),
                (["p25-b27"], "SLIP + SHIFT + 1 OR 2 PUNCHES STANCE"),
                (["p25-b28"], "JAB + ANY DEFENCE + 2 PUNCHES"),
            ], durationSeconds: 180, restSeconds: 0),
            "basic-w5-d2-p32-s7-1": Snapshot(items: [
                ("p32-b21", "VIRTUAL PAD WORK. 5 RUNDS OF 3 MINUTES"),
                ("p32-b22", "ALL SINGLE PUNCHES WITH STEPS BACK IN FRONTAL STANCE"),
                ("p32-b23", "SIDESTEP COUNTERS IN FONTAL STANCE"),
                ("p32-b24", "PUNCHES WITH STEPS BACK IN THE FIGHTING STANCE"),
                ("p32-b25", "ANY DEFENCE + 2 PUNCHES"),
                ("p32-b27", "JAB + ANY DEFENCE + 2 PUNCHES"),
            ], focuses: [
                (["p32-b22"], "ALL SINGLE PUNCHES WITH STEPS BACK IN FRONTAL STANCE"),
                (["p32-b23"], "SIDESTEP COUNTERS IN FONTAL STANCE"),
                (["p32-b24"], "PUNCHES WITH STEPS BACK IN THE FIGHTING STANCE"),
                (["p32-b25"], "ANY DEFENCE + 2 PUNCHES"),
                (["p32-b27"], "JAB + ANY DEFENCE + 2 PUNCHES"),
            ], durationSeconds: 180, restSeconds: 0),
        ]
        guard let snapshot = snapshots[id], completion == .manual, kind == .boxing,
              rounds == nil, durationSeconds == nil, restSeconds == nil,
              let items = sourceItems,
              items.map({ ($0.id, $0.text) }).elementsEqual(snapshot.items, by: { $0.0 == $1.0 && $0.1 == $1.1 }),
              items.map(\.text).joined(separator: "\n") == instructions,
              sourceText == instructions else { return nil }
        let final = snapshot.focuses.count - 1
        return snapshot.focuses.enumerated().map { index, focus in
            ReviewedRoundStep(sourceItemIDs: focus.0, focusText: focus.1,
                              durationSeconds: snapshot.durationSeconds,
                              restSeconds: index == final ? 0 : snapshot.restSeconds)
        }
    }

    func roundSequenceDemoURLs(for itemIDs: [String]) -> [String] {
        var seen = Set<String>()
        let selected = (sourceItems ?? []).filter { itemIDs.contains($0.id) }
        return selected.flatMap { $0.demoURLs ?? [] }.filter { seen.insert($0).inserted }
    }

    struct ReviewedLinkedRunStep {
        let title: String
        let instructions: String
        let sourceURL: String
        let kind: SessionBlockKind
        let durationSeconds: Int
        let restSeconds: Int
        let prescription: String?
        let completion: BlockCompletionMode
        let activityKey: String?
        let drillID: String?
    }

    /// Expands the two linked public running documents only for the five source
    /// blocks that carry those exact links. Ranges and distance-based work stay
    /// manual so the runtime does not turn an editorial ambiguity into a clock.
    /// The interval document prescribes 3-6 fast rounds and then enumerates six;
    /// rounds four through six are labeled optional and remain skippable.
    var reviewedLinkedRunSteps: [ReviewedLinkedRunStep]? {
        struct Snapshot {
            let sourceURL: String
            let title: String
            let instructions: String
            let items: [(String, String)]
            let linkedItemID: String
            let documentURL: String
            let kind: String
        }
        let steadyURL = "https://docs.google.com/document/d/1T44tF70cpGnjE2AakliGlj6Awt2fPvmhox1IqNi-jbA/edit?usp=sharing"
        let intervalURL = "https://docs.google.com/document/d/1mLJtuKeCIFc4wX_DfA4FH6SmoarMV8-Hp9IQWDqPjLE/edit?usp=sharing"
        let snapshots: [String: Snapshot] = [
            "competitive-w1-d6-p10-s1-1": Snapshot(
                sourceURL: "https://boxing.dharmicdata.org/program/competitive/week/1/day/6#p10-s1",
                title: "ENDURANCE WORKOUT #1",
                instructions: "ENDURANCE WORKOUT #1\nsteady state run (click and open\na Google Doc)",
                items: [("p10-b1", "ENDURANCE WORKOUT #1"),
                        ("p10-b2", "steady state run (click and open"),
                        ("p10-b3", "a Google Doc)")],
                linkedItemID: "p10-b2", documentURL: steadyURL, kind: "steady"),
            "competitive-w5-d4-p40-s9-1": Snapshot(
                sourceURL: "https://boxing.dharmicdata.org/program/competitive/week/5/day/4#p40-s9",
                title: "steady state run",
                instructions: "steady state run\n(click and open a Google Doc)",
                items: [("p40-b28", "steady state run"),
                        ("p40-b29", "(click and open a Google Doc)")],
                linkedItemID: "p40-b29", documentURL: steadyURL, kind: "steady"),
            "competitive-w3-d6-p26-s1-1": Snapshot(
                sourceURL: "https://boxing.dharmicdata.org/program/competitive/week/3/day/6#p26-s1",
                title: "ENDURANCE WORKOUT #3",
                instructions: "ENDURANCE WORKOUT #3\ninterval run (click and open\na Google Doc)",
                items: [("p26-b1", "ENDURANCE WORKOUT #3"),
                        ("p26-b2", "interval run (click and open"),
                        ("p26-b3", "a Google Doc)")],
                linkedItemID: "p26-b2", documentURL: intervalURL, kind: "interval"),
            "basic-w2-d4-p13-s11-1": Snapshot(
                sourceURL: "https://boxing.dharmicdata.org/program/basic/week/2/day/4#p13-s11",
                title: "DON’T FEEL LIKE LIFTING TODAY?!",
                instructions: "DON’T FEEL LIKE LIFTING TODAY?!\nALTERNATIVE RUNNING WORKOUT",
                items: [("p13-b54", "DON’T FEEL LIKE LIFTING TODAY?!"),
                        ("p13-b55", "ALTERNATIVE RUNNING WORKOUT")],
                linkedItemID: "p13-b55", documentURL: intervalURL, kind: "interval"),
            "basic-w3-d4-p20-s10-1": Snapshot(
                sourceURL: "https://boxing.dharmicdata.org/program/basic/week/3/day/4#p20-s10",
                title: "DON’T FEEL LIKE LIFTING TODAY?!",
                instructions: "DON’T FEEL LIKE LIFTING TODAY?!\nALTERNATIVE RUNNING WORKOUT",
                items: [("p20-b53", "DON’T FEEL LIKE LIFTING TODAY?!"),
                        ("p20-b54", "ALTERNATIVE RUNNING WORKOUT")],
                linkedItemID: "p20-b54", documentURL: intervalURL, kind: "interval"),
        ]
        guard let snapshot = snapshots[id], completion == .manual, kind == .boxing,
              drillID == "free-boxing-v1", activityKey == nil,
              rounds == nil, durationSeconds == nil, restSeconds == nil,
              title == snapshot.title, instructions == snapshot.instructions,
              sourceText == snapshot.instructions, sourceURL == snapshot.sourceURL,
              referenceURLs?.contains(snapshot.documentURL) == true,
              let items = sourceItems,
              items.map({ ($0.id, $0.text) }).elementsEqual(snapshot.items,
                  by: { $0.0 == $1.0 && $0.1 == $1.1 }),
              let linked = items.first(where: { $0.id == snapshot.linkedItemID }),
              linked.referenceURLs == [snapshot.documentURL], linked.demoURLs?.isEmpty == true else { return nil }
        return snapshot.kind == "steady" ? steadyRunSteps(sourceURL: snapshot.documentURL)
                                           : intervalRunSteps(sourceURL: snapshot.documentURL)
    }

    private func steadyRunSteps(sourceURL: String) -> [ReviewedLinkedRunStep] {
        let warmup = "Start the workout with a dynamic full-body warm-up.\n" + Self.linkedRunWarmupList
        let shadow = "After the run you should be a bit tired and that is a perfect time to shadow box. Go for 3 rounds of 3 minutes with one minute of rest in between the rounds. Focus on staying relaxed, being your flow and keeping it realistic."
        var steps = [ReviewedLinkedRunStep(title: "Dynamic full-body warm-up", instructions: warmup,
            sourceURL: sourceURL, kind: .warmup, durationSeconds: 0, restSeconds: 0,
            prescription: nil, completion: .manual, activityKey: nil, drillID: nil),
            ReviewedLinkedRunStep(title: "30-minute moderate run",
                instructions: "The main part of the workout includes running with a moderate pace (around 135-145 heart beat rate) for 30 minutes with no breaks.",
                sourceURL: sourceURL, kind: .exercise, durationSeconds: 1_800, restSeconds: 0,
                prescription: "Around 135-145 heart beat rate", completion: .timed,
                activityKey: nil, drillID: nil)]
        for round in 1...3 {
            steps.append(ReviewedLinkedRunStep(title: "Shadow box · Round \(round) of 3",
                instructions: shadow, sourceURL: sourceURL, kind: .boxing, durationSeconds: 180,
                restSeconds: round < 3 ? 60 : 0, prescription: nil, completion: .timed,
                activityKey: "shadowboxing", drillID: "free-boxing-v1"))
        }
        steps.append(ReviewedLinkedRunStep(title: "Static stretches",
            instructions: "Static stretches: finish off your workout with a series of static stretches to help your muscles recover and prevent any tightness.\n" + Self.linkedRunStaticStretchList,
            sourceURL: sourceURL, kind: .cooldown, durationSeconds: 0, restSeconds: 0,
            prescription: nil, completion: .manual, activityKey: nil, drillID: nil))
        return steps
    }

    private func intervalRunSteps(sourceURL: String) -> [ReviewedLinkedRunStep] {
        let warmup = "Start the workout with a dynamic full-body warm-up.\n" + Self.linkedRunWarmupList
        let preface = "The main part of the workout includes 3-6 rounds of interval running where instead of rest you jog at a slow pace:"
        var steps = [ReviewedLinkedRunStep(title: "Dynamic full-body warm-up", instructions: warmup,
            sourceURL: sourceURL, kind: .warmup, durationSeconds: 0, restSeconds: 0,
            prescription: nil, completion: .manual, activityKey: nil, drillID: nil)]
        for round in 1...6 {
            let restLabel = round == 5 ? "RestT: 1 minute of light jogging" : "Rest: 1 minute of light jogging"
            let lines = round < 6
                ? "\(preface)\nRound \(round): 3 minutes of running at a fast pace\n\(restLabel)"
                : "\(preface)\nRound 6: 3 minutes of running at a fast pace"
            steps.append(ReviewedLinkedRunStep(
                title: (round > 3 ? "Optional fast run" : "Fast run") + " · Round \(round) of 6",
                instructions: lines, sourceURL: sourceURL, kind: .exercise,
                durationSeconds: 180, restSeconds: round < 6 ? 60 : 0,
                prescription: round > 3 ? "Optional · source prescribes 3-6 rounds" : nil,
                completion: .timed, activityKey: nil, drillID: nil))
        }
        steps.append(Self.manualLinkedRunStep(title: "Walk 3-4 minutes",
            instructions: "Rest:\n3-4 minutes of walking", sourceURL: sourceURL, kind: .recovery))
        for round in 1...3 {
            steps.append(Self.manualLinkedRunStep(title: "100-meter sprint · Round \(round) of 3",
                instructions: "Round \(round): 100-meter sprint", sourceURL: sourceURL, kind: .exercise,
                prescription: "100 meters"))
            if round < 3 {
                steps.append(Self.manualLinkedRunStep(title: "Walk 1.5-2 minutes",
                    instructions: (round == 1 ? "Rest" : "Res") + ": 1.5 - 2 minutes of walking",
                    sourceURL: sourceURL, kind: .recovery))
            }
        }
        steps.append(Self.manualLinkedRunStep(title: "Walk 3-4 minutes",
            instructions: "Rest: 3-4 minutes of walking", sourceURL: sourceURL, kind: .recovery))
        let shuttle = "The final part of the workout consists of 8-15 meter shuttles. Run 8 meters forward, then turn around and run 8 meters back, then turn and run 15 meters forward, turn around and run 15 meters back. That would be one 8-15 meter shuttle:"
        for round in 1...3 {
            let restLabel = round == 1 ? "Resr" : "Rest"
            let lines = round < 3
                ? "\(shuttle)\nRound \(round): Perform 8-15 meter shuttles (as described above)\n\(restLabel): 1 minute of walking"
                : "\(shuttle)\nRound 3: Perform 8-15 meter shuttles (as described above)"
            steps.append(ReviewedLinkedRunStep(title: "8-15 meter shuttles · Round \(round) of 3",
                instructions: lines, sourceURL: sourceURL, kind: .exercise,
                durationSeconds: 0, restSeconds: round < 3 ? 60 : 0,
                prescription: "8m out/back + 15m out/back", completion: .manual,
                activityKey: nil, drillID: nil))
        }
        steps.append(Self.manualLinkedRunStep(title: "Walk 3-4 minutes",
            instructions: "Rest: 3-4 minutes of walking", sourceURL: sourceURL, kind: .recovery))
        steps.append(Self.manualLinkedRunStep(title: "Static stretches",
            instructions: "Static stretches: finish off your workout with a series of static stretches to help your muscles recover and prevent any tightness.\n" + Self.linkedRunStaticStretchList,
            sourceURL: sourceURL, kind: .cooldown))
        return steps
    }

    private static func manualLinkedRunStep(title: String, instructions: String, sourceURL: String,
                                            kind: SessionBlockKind, prescription: String? = nil)
        -> ReviewedLinkedRunStep {
        ReviewedLinkedRunStep(title: title, instructions: instructions, sourceURL: sourceURL,
            kind: kind, durationSeconds: 0, restSeconds: 0, prescription: prescription,
            completion: .manual, activityKey: nil, drillID: nil)
    }

    private static let linkedRunWarmupList = "Ankle circles, calves stretch, leg swings forward and to the sides, hip openers, 90-90s, high knee run, buttkicks, feet kick outs forward and backward, deep controlled squats, wall sit, shoulder circles, arm swings vertical and horizontal, elbow circles, wrists circles, neck twists and turn, torso bends, torso circles, torso twist, floor touches, cossack squats."
    private static let linkedRunStaticStretchList = "Wide fold, calves stretch, quad stretch, knee over toes lunge position, side lunge hold."

    struct EnduranceCircuitStep {
        let item: WorkoutSourceItem
        let circuit: Int
        let restSeconds: Int
    }

    /// Two source-pinned endurance days prescribe the same complete circuit:
    /// three passes over ten named exercises, one minute of work, 30 seconds
    /// between exercises, and two minutes between circuits. Keep changed or
    /// incomplete source snapshots manual rather than guessing a schedule.
    var reviewedEnduranceCircuitSteps: [EnduranceCircuitStep]? {
        let pages: [String: Int] = [
            "competitive-w2-d6-p18-s1-1": 18,
            "competitive-w4-d6-p34-s1-1": 34,
        ]
        guard let page = pages[id], completion == .manual, kind == .exercise,
              rounds == nil, durationSeconds == nil, restSeconds == nil,
              let items = sourceItems, items.count == 15,
              items.map(\.id) == (1...15).map({ "p\(page)-b\($0)" }),
              items.map(\.text) == [
                "WARM UP:", "ENDURANCE WORKOUT #\(page == 18 ? 2 : 4) WARM UP:",
                "3 CIRCUITS, 10 EXERCISES EACH. WORK FOR 1 MINUTE, REST FOR",
                "30 SECONDS. TAKE 2 MINUTES OF REST BETWEEN CIRCUITS",
                "Push-Up Shuttle", "Squat With Med Ball Throws", "Rolls", "Plate Punches",
                "Side Jumps", "Plank", "Landmine Punches", "Boxing Steps With Weights",
                "Wall Sit", "Barbell Push-Outs", "Stretch Series",
              ],
              items.map(\.text).joined(separator: "\n") == instructions,
              sourceText == instructions else { return nil }
        let exercises = Array(items[4..<14])
        return (1...3).flatMap { circuit in
            exercises.enumerated().map { index, item in
                let isFinal = circuit == 3 && index == exercises.count - 1
                let isCircuitBoundary = index == exercises.count - 1
                return EnduranceCircuitStep(item: item, circuit: circuit,
                    restSeconds: isFinal ? 0 : (isCircuitBoundary ? 120 : 30))
            }
        }
    }

    var reviewedWholeBlockItemID: String? {
        activityKey == nil && reviewedWholeBlockActivityKey == "squat_jumps" ? sourceItems?.first?.id : nil
    }

    /// A complete one-line source prescription can identify the movement without
    /// implying that a repetition was seen. This mapping is tied to exact items;
    /// mixed conditioning sections must remain unassigned.
    var reviewedWholeBlockActivityKey: String? {
        if let activityKey { return activityKey }
        if id == "basic-w1-d5-p7-s6-4", completion == .manual,
           title == "CONDITIONING BAG WORK DRILL (1 ROUND)", instructions == title,
           sourceText == title { return "bag_work" }
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
        if title == instructions, sourceText == instructions {
            if title == "DYNAMIC WARM-UP:" || title == "STRETCHES" { return "mobility" }
        }
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
