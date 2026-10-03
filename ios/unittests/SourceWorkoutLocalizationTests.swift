import XCTest
@testable import Coin

@MainActor final class SourceWorkoutLocalizationTests: XCTestCase {
    private var lesson: WorkoutLesson {
        get throws { try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d1" }) }
    }

    private func changedOverlay(_ edit: (inout [String: Any]) -> Void) throws -> SourceWorkoutFrenchOverlay {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "BasicW1D1French", withExtension: "json"))
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        edit(&raw)
        return try JSONDecoder().decode(SourceWorkoutFrenchOverlay.self,
                                        from: JSONSerialization.data(withJSONObject: raw))
    }

    private func syntheticReviewedOverlay(for lesson: WorkoutLesson) throws -> SourceWorkoutFrenchOverlay {
        let raw: [String: Any] = [
            "schemaVersion": 1, "lessonID": lesson.id, "sourceSHA256": lesson.sourceSHA256,
            "sourceTitleFR": "Séance test", "status": "reviewed", "reviewFlags": [:],
            "blocks": lesson.blocks.map { block in
                ["blockID": block.id, "sourceTitle": block.title,
                 "sourceInstructions": block.instructions, "titleFR": "FR " + block.title,
                 "instructionsFR": "FR " + block.instructions,
                 "sourceItems": (block.sourceItems ?? []).map { item in
                    ["itemID": item.id, "sourceText": item.text, "textFR": "FR " + item.text]
                 }] as [String: Any]
            },
        ]
        return try JSONDecoder().decode(SourceWorkoutFrenchOverlay.self,
            from: JSONSerialization.data(withJSONObject: raw))
    }

    func testCompletePinnedDayDisplaysFrenchWithoutChangingSourceOrTiming() throws {
        let lesson = try lesson
        let overlay = try XCTUnwrap(SourceWorkoutFrenchOverlay.bundled)
        XCTAssertEqual(overlay.validated(for: lesson)?.count, 13)
        XCTAssertEqual(overlay.blocks.reduce(0) { $0 + $1.sourceItems.count }, 30)
        let template = lesson.template()
        XCTAssertEqual(template.localizedSourceTitleFR, "Séance n° 1")
        XCTAssertTrue(template.blocks.allSatisfy { $0.localizedSourceTitleFR != nil &&
            $0.localizedSourceInstructionsFR != nil })
        XCTAssertEqual(template.blocks.first?.displaySourceTitle(language: "fr"), "Échauffement dynamique :")
        XCTAssertEqual(template.blocks.first?.displaySourceTitle(language: "en"), "DYNAMIC WARM-UP:")
        XCTAssertEqual(template.blocks.first?.sourceSpeechLanguage(displayLanguage: "fr"), "fr")
        XCTAssertEqual(template.blocks.first?.sourceInstructions, lesson.blocks.first?.instructions)
        XCTAssertEqual(template.blocks.filter { $0.sourceBlockID == "basic-w1-d1-p3-s3-1" }
            .map(\.effectiveSeconds), [120, 120, 120, 120])
        XCTAssertEqual(template.blocks.filter { $0.sourceBlockID == "basic-w1-d1-p3-s3-1" }
            .map(\.effectiveRestSeconds), [30, 30, 30, 0])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(directory: folder)
        let sessionID = store.start(template, origin: .synthetic)
        let block = try XCTUnwrap(template.blocks.first)
        store.recordCueRequest(sessionID: sessionID, blockID: block.id,
                               cueKey: "source_instruction", language: "fr", trigger: "stage_start")
        let restored = try XCTUnwrap(TrainingStore(directory: folder).data.sessions.first)
        XCTAssertEqual(restored.localizedSourceTitleFR, "Séance n° 1")
        XCTAssertEqual(restored.blocks.first?.sourceInstructions, block.sourceInstructions)
        XCTAssertEqual(restored.blocks.first?.localizedSourceInstructionsFR, block.localizedSourceInstructionsFR)
        XCTAssertEqual(restored.cueRequests?.first?.language, "fr")
    }

    func testAnyMismatchOrPartialCandidateFallsBackForEntireDay() throws {
        let lesson = try lesson
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["status"] = "candidate" },
            { $0["sourceSHA256"] = "different-source" },
            { raw in var blocks = raw["blocks"] as! [[String: Any]]; blocks.removeLast(); raw["blocks"] = blocks },
            { raw in var blocks = raw["blocks"] as! [[String: Any]];
                blocks[0]["sourceInstructions"] = "CHANGED"; raw["blocks"] = blocks },
            { raw in var blocks = raw["blocks"] as! [[String: Any]];
                var items = blocks[0]["sourceItems"] as! [[String: Any]];
                items[0]["sourceText"] = "CHANGED"; blocks[0]["sourceItems"] = items; raw["blocks"] = blocks },
            { raw in var blocks = raw["blocks"] as! [[String: Any]];
                blocks[1]["instructionsFR"] = "4 rounds de 3 minutes, avec 30 secondes de repos.";
                raw["blocks"] = blocks },
        ]
        for change in changes {
            let overlay = try changedOverlay(change)
            XCTAssertNil(overlay.validated(for: lesson))
        }
        let other = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d2" })
        XCTAssertNil(SourceWorkoutFrenchOverlay.bundled?.validated(for: other))
        XCTAssertTrue(other.template().blocks.allSatisfy { $0.localizedSourceTitleFR == nil &&
            $0.sourceSpeechLanguage(displayLanguage: "fr") == "en" })
    }

    func testFutureDayRequiresReviewedStatusAndCompletePinnedSource() throws {
        let original = try lesson
        let futureID = "basic-w1-d70"
        let futureSHA = String(repeating: "a", count: 64)
        let sourceURL = try XCTUnwrap(Bundle.main.url(forResource: "WorkoutCatalog", withExtension: "json"))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: sourceURL)) as? [String: Any])
        let workouts = try XCTUnwrap(catalog["workouts"] as? [[String: Any]])
        var lessonJSON = try XCTUnwrap(workouts.first { ($0["id"] as? String) == original.id })
        lessonJSON["id"] = futureID
        lessonJSON["sourceSHA256"] = futureSHA
        let future = try JSONDecoder().decode(WorkoutLesson.self,
            from: JSONSerialization.data(withJSONObject: lessonJSON))
        let provisional = try changedOverlay { raw in
            raw["lessonID"] = futureID
            raw["sourceSHA256"] = futureSHA
        }
        XCTAssertNil(provisional.validated(for: future))
        let reviewed = try changedOverlay { raw in
            raw["lessonID"] = futureID
            raw["sourceSHA256"] = futureSHA
            raw["status"] = "reviewed"
        }
        XCTAssertEqual(reviewed.validated(for: future)?.count, original.blocks.count)
        XCTAssertNil(reviewed.validated(for: original))
        XCTAssertNil(SourceWorkoutFrenchOverlay.bundled(for: futureID))
        XCTAssertNil(SourceWorkoutFrenchOverlay.bundled(for: "../BasicW1D1French"))
    }

    func testExpandedManualStepsTranslateExactSourceItemLines() throws {
        let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d6" })
        let english = lesson.template().blocks
        let overlay = try syntheticReviewedOverlay(for: lesson)
        let localized = try XCTUnwrap(overlay.localizedBlocks(for: lesson, blocks: english))
        XCTAssertGreaterThan(localized.count, 1)
        XCTAssertEqual(localized.map(\.sourceItemID), english.map(\.sourceItemID))
        XCTAssertEqual(localized.map(\.sourceInstructions), english.map(\.sourceInstructions))
        XCTAssertTrue(localized.allSatisfy { $0.localizedSourceTitleFR == "FR " + ($0.sourceTitle ?? "") })
        XCTAssertTrue(localized.allSatisfy { block in
            let englishLines = (block.sourceInstructions ?? "").components(separatedBy: "\n")
            let frenchLines = (block.localizedSourceInstructionsFR ?? "").components(separatedBy: "\n")
            return frenchLines == englishLines.map { "FR " + $0 }
        })
        var bad = english
        bad[1].sourceInstructions = (bad[1].sourceInstructions ?? "") + "\nUNMAPPED"
        XCTAssertNil(overlay.localizedBlocks(for: lesson, blocks: bad))
    }

    func testPadRoundFocusUsesExactItemAndHeading() throws {
        let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "competitive-w1-d4" })
        let english = lesson.template().blocks
        let overlay = try syntheticReviewedOverlay(for: lesson)
        let localized = try XCTUnwrap(overlay.localizedBlocks(for: lesson, blocks: english))
        let padID = "competitive-w1-d4-p8-s4-1"
        let rounds = localized.filter { $0.sourceBlockID == padID }
        XCTAssertEqual(rounds.count, 5)
        XCTAssertEqual(Set(rounds.compactMap(\.sourceItemID)).count, 5)
        for round in rounds {
            XCTAssertEqual(round.localizedSourceTitleFR, "FR " + (round.sourceTitle ?? ""))
            XCTAssertEqual(round.localizedSourceInstructionsFR,
                           "FR VIRTUAL PAD WORK (5 ROUNDS OF 3 MINUTES)\nFR " + (round.sourceTitle ?? ""))
        }
        var bad = english
        let index = try XCTUnwrap(bad.firstIndex { $0.sourceBlockID == padID })
        bad[index].sourceTitle = "DIFFERENT FOCUS"
        XCTAssertNil(overlay.localizedBlocks(for: lesson, blocks: bad))
    }
}
