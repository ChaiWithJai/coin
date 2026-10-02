import XCTest
@testable import Coin

@MainActor final class WorkoutCatalogTests: XCTestCase {
    func testOldBlockDecodesWithoutSourceFields() throws {
        let old = """
        {"id":"00000000-0000-0000-0000-000000000001","kind":"boxing","minutes":3,"roundNumber":1,"drillID":"probe-combine-angle-v1","restAfterMinutes":1}
        """
        let block = try JSONDecoder().decode(SessionBlock.self, from: Data(old.utf8))
        XCTAssertEqual(block.effectiveSeconds, 180)
        XCTAssertEqual(block.effectiveRestSeconds, 60)
        XCTAssertFalse(block.isManual)
        XCTAssertNil(block.sourceInstructions)
    }

    func testFreestyleKeepsExactSecondsAndHasNoFinalRest() throws {
        let template = try XCTUnwrap(SessionTemplates.freestyle(rounds: 3, roundSeconds: 45, restSeconds: 15))
        XCTAssertEqual(template.plannedSeconds, 165)
        XCTAssertEqual(template.plannedMinutes, 3)
        XCTAssertEqual(template.blocks.map(\.effectiveRestSeconds), [15, 15, 0])
        XCTAssertTrue(template.blocks.allSatisfy { $0.drillID == "free-boxing-v1" && $0.effectiveSeconds == 45 })
        XCTAssertNil(SessionTemplates.freestyle(rounds: 0))
    }

    func testSourceCatalogPreservesPrescriptionAndManualWork() throws {
        let catalog = try WorkoutCatalog.load(Data(fixture.utf8))
        let template = try XCTUnwrap(catalog.lessons.first).template()
        XCTAssertEqual(template.sourceURL, "https://boxing.dharmicdata.org/test")
        XCTAssertEqual(template.blocks.count, 3)
        XCTAssertEqual(template.blocks.map(\.effectiveSeconds), [45, 45, 0])
        XCTAssertEqual(template.blocks.map(\.effectiveRestSeconds), [15, 0, 0])
        XCTAssertEqual(template.blocks.last?.sourceInstructions, "3 sets of 10 push-ups. Rest as needed.")
        XCTAssertEqual(template.blocks.last?.sourceDemoURLs, ["https://example.org/demo"])
        XCTAssertEqual(template.blocks.last?.sourceActivityKey, "pushups")
        XCTAssertTrue(template.blocks.last?.isManual == true)
    }

    func testManualProgressSurvivesRestartWithoutInventedDurationOrTimerCompletion() throws {
        let template = try XCTUnwrap(WorkoutCatalog.load(Data(fixture.utf8)).lessons.first).template()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(directory: folder)
        let sessionID = store.start(template)
        let block = try XCTUnwrap(template.blocks.last)
        store.recordTimedSeconds(sessionID: sessionID, seconds: 240)
        store.saveRuntime(sessionID: sessionID, segmentIndex: 2, remainingSeconds: 0, elapsedSeconds: 135)
        store.recordSegment(sessionID: sessionID, blockID: block.id, activityKey: "pushups", isRest: false,
                            plannedSeconds: 0, elapsedSeconds: 135, exitReason: "timer_elapsed")
        XCTAssertTrue(store.data.sessions[0].segmentLogs?.isEmpty == true)
        store.recordSegment(sessionID: sessionID, blockID: block.id, activityKey: "pushups", isRest: false,
                            plannedSeconds: 0, elapsedSeconds: 135, exitReason: "manual_completed")
        store.completeBlock(sessionID: sessionID, blockID: block.id, source: "manual_completed")
        let restored = try XCTUnwrap(TrainingStore(directory: folder).data.sessions.first)
        XCTAssertEqual(restored.timerElapsedSeconds, 240)
        XCTAssertEqual(restored.runtimeElapsedSeconds, 135)
        XCTAssertEqual(restored.sourceVersion, "source-hash")
        XCTAssertEqual(restored.segmentLogs?.first?.exitReason, "manual_completed")
        XCTAssertEqual(restored.segmentLogs?.first?.elapsedSeconds, 135)
        XCTAssertEqual(restored.blockLogs?.first?.evidenceSource, "manual_completed")
    }

    func testInvalidTimedSourceDoesNotSilentlyInventDuration() throws {
        let malformed = fixture.replacingOccurrences(of: "\"durationSeconds\":45", with: "\"durationSeconds\":null")
        XCTAssertThrowsError(try WorkoutCatalog.load(Data(malformed.utf8)))
    }

    func testSourceInstructionsKeepTheirActualLanguageInTelemetry() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let template = try XCTUnwrap(WorkoutCatalog.load(Data(fixture.utf8)).lessons.first).template()
        let store = TrainingStore(directory: folder)
        let sessionID = store.start(template)
        let block = try XCTUnwrap(template.blocks.first)
        store.recordCueRequest(sessionID: sessionID, blockID: block.id, cueKey: "source_instruction",
                               language: "fr", trigger: "stage_start")
        XCTAssertTrue(store.data.sessions[0].cueRequests?.isEmpty == true)
        store.recordCueRequest(sessionID: sessionID, blockID: block.id, cueKey: "source_instruction",
                               language: "en", trigger: "stage_start")
        XCTAssertEqual(store.data.sessions[0].cueRequests?.first?.language, "en")
    }

    func testBundledCatalogLoadsEverySourceDayWithoutInventingManualDurations() throws {
        let catalog = WorkoutCatalog.shared
        XCTAssertNil(catalog.error)
        XCTAssertEqual(catalog.lessons.count, 70)
        for lesson in catalog.lessons {
            let template = lesson.template()
            XCTAssertEqual(template.sourceVersion, lesson.sourceSHA256)
            XCTAssertFalse(template.blocks.isEmpty)
            XCTAssertTrue(template.blocks.filter(\.isManual).allSatisfy { $0.effectiveSeconds == 0 })
            XCTAssertTrue(template.blocks.allSatisfy { $0.sourceBlockID != nil && $0.sourceInstructions != nil })
        }
        let first = try XCTUnwrap(catalog.lessons.first { $0.id == "basic-w1-d1" }).template()
        let frontal = first.blocks.filter { $0.sourceTitle == "FR0NTAL STANCE DRILL" }
        XCTAssertEqual(frontal.map(\.effectiveSeconds), [120, 120, 120, 120])
        XCTAssertEqual(frontal.map(\.effectiveRestSeconds), [30, 30, 30, 0])
    }

    func testExplicitStrengthItemsKeepTheirOwnPrescriptionAndProvenance() throws {
        let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d6" })
        let source = try XCTUnwrap(lesson.blocks.first)
        let blocks = lesson.template().blocks
        XCTAssertEqual(blocks.map(\.sourceTitle), ["Squat", "Pallof Press", "Hip Airplanes", "Scap Push-Up",
            "Depth Drop", "Kettlebell Swing", "Stretch Series", "Plyo Push-Up", "Inverted Row",
            "Dumbbell Overhead Walk (20 Steps Each)"])
        XCTAssertEqual(blocks.map(\.sourceItemID), ["p8-b6", "p8-b7", "p8-b8", "p8-b9", "p8-b10",
            "p8-b11", "p8-b16", "p8-b15", "p8-b17", "p8-b18"])
        for (index, block) in blocks.enumerated() {
            let prescription = index < 6 ? "3 SETS OF 10 REPS EACH EXERCISE" : "2 SETS OF 5-8 REPS EACH EXERCISE"
            let item = try XCTUnwrap(source.sourceItems?.first { $0.id == block.sourceItemID })
            XCTAssertEqual(block.sourceBlockID, source.id)
            XCTAssertEqual(block.repetitionText, prescription)
            XCTAssertEqual(block.sourceInstructions, "WARM UP:\nLIFT #3 WARM UP:\n" + prescription + "\n" + item.text)
            XCTAssertEqual(block.sourceDemoURLs, item.demoURLs)
            XCTAssertEqual(block.sourceURL, source.sourceURL ?? lesson.sourceURL)
            XCTAssertTrue(block.isManual)
            XCTAssertEqual(block.effectiveSeconds, 0)
            XCTAssertEqual(block.effectiveRestSeconds, 0)
            XCTAssertNil(block.roundNumber)
            XCTAssertNil(block.sourceActivityKey)
        }
    }

    func testExplicitCombinationsAreTwelveManualItemsNotInventedRounds() throws {
        for week in 1...5 {
            let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w\(week)-d3" })
            let source = try XCTUnwrap(lesson.blocks.first { $0.title == "SHADOW BOXING: PRACTICE 5 TIMES EACH OF THE 12 COMBOS" })
            let items = try XCTUnwrap(source.sourceItems).dropFirst()
            let blocks = lesson.template().blocks.filter { $0.sourceBlockID == source.id }
            XCTAssertEqual(blocks.count, 12)
            XCTAssertEqual(blocks.map(\.sourceItemID), items.map { Optional($0.id) })
            XCTAssertEqual(blocks.map(\.sourceTitle), items.map { Optional($0.text) })
            XCTAssertEqual(blocks.map(\.sourceDemoURLs), items.map(\.demoURLs))
            XCTAssertTrue(blocks.allSatisfy { $0.kind == .exercise && $0.roundNumber == nil && $0.isManual
                && $0.effectiveSeconds == 0 && $0.effectiveRestSeconds == 0 && $0.repetitionText == source.title })
        }
    }

    func testAmbiguousManualSectionsRemainWholeWithAllOriginalText() throws {
        for lessonID in ["basic-w4-d4", "basic-w4-d6", "basic-w5-d6"] {
            let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == lessonID })
            for source in lesson.blocks where source.completion == .manual {
                let blocks = lesson.template().blocks.filter { $0.sourceBlockID == source.id }
                XCTAssertEqual(blocks.count, 1, source.id)
                XCTAssertNil(blocks.first?.sourceItemID)
                XCTAssertEqual(blocks.first?.sourceInstructions, source.instructions)
                XCTAssertEqual(blocks.first?.sourceDemoURLs, source.demoURLs)
            }
        }
    }

    func testManualItemProgressPersistsWithoutFinishingItsWholeWorkout() throws {
        let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d6" })
        let template = lesson.template()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(directory: folder)
        let sessionID = store.start(template)
        let first = try XCTUnwrap(template.blocks.first)
        store.recordSegment(sessionID: sessionID, blockID: first.id, activityKey: nil, isRest: false,
                            plannedSeconds: 0, elapsedSeconds: 40, exitReason: "manual_completed")
        store.completeBlock(sessionID: sessionID, blockID: first.id, source: "manual_completed")
        store.saveRuntime(sessionID: sessionID, segmentIndex: 1, remainingSeconds: 0, elapsedSeconds: 0)
        let restored = try XCTUnwrap(TrainingStore(directory: folder).data.sessions.first)
        XCTAssertEqual(restored.state, .active)
        XCTAssertEqual(restored.completedBlockIDs, [first.id])
        XCTAssertEqual(restored.runtimeSegmentIndex, 1)
        XCTAssertEqual(restored.blocks[1].sourceItemID, "p8-b7")
        XCTAssertEqual(restored.blocks[1].sourceTitle, "Pallof Press")
        XCTAssertEqual(restored.blockLogs?.first?.evidenceSource, "manual_completed")
    }

    func testConservativeItemCoverageLeavesOtherSourceSectionsUnchanged() throws {
        var expandedSections = 0
        var expandedItems = 0
        for lesson in WorkoutCatalog.shared.lessons {
            let blocks = lesson.template().blocks
            for source in lesson.blocks {
                let mapped = blocks.filter { $0.sourceBlockID == source.id }
                if mapped.contains(where: { $0.sourceItemID != nil }) {
                    expandedSections += 1
                    expandedItems += mapped.count
                    XCTAssertTrue(mapped.allSatisfy { $0.sourceItemID != nil })
                } else {
                    XCTAssertEqual(mapped.count, source.completion == .timed ? (source.rounds ?? 1) : 1)
                    XCTAssertTrue(mapped.allSatisfy { $0.sourceInstructions == source.instructions })
                }
            }
        }
        XCTAssertEqual(expandedSections, 22)
        XCTAssertEqual(expandedItems, 218)
    }

    private var fixture: String { """
    {"schemaVersion":1,"workouts":[{"id":"source-test","program":"boxing","week":1,"day":1,"title":"Source workout","sourceURL":"https://boxing.dharmicdata.org/test","sourceSHA256":"source-hash","blocks":[{"id":"a","title":"Shadowboxing","instructions":"Two rounds, 45 seconds each. Rest 15 seconds between rounds.","kind":"boxing","drillID":"free-boxing-v1","rounds":2,"durationSeconds":45,"restSeconds":15,"completion":"timed"},{"id":"b","title":"Push-ups","instructions":"3 sets of 10 push-ups. Rest as needed.","kind":"exercise","activityKey":"pushups","reps":"10 reps","sets":3,"completion":"manual","demoURLs":["https://example.org/demo"]}]}]}
    """ }
}

@MainActor final class RoundReportRecoveryTests: XCTestCase {
    func testOnlyValidReportedSummariesStopRetrying() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sessionID = UUID()
        let pendingID = UUID().uuidString
        let summary = RoundSummary(requestID: pendingID, language: "fr", stance: "orthodox", drillID: "free-boxing-v1",
                                   round: 1, durationS: 180, exchanges: [], sessionID: sessionID.uuidString, workoutMode: "freestyle")
        try JSONEncoder().encode(summary).write(to: folder.appendingPathComponent("pending-summary.json"))
        var completed = summary
        completed.requestID = UUID().uuidString
        completed.round = 2
        try JSONEncoder().encode(completed).write(to: folder.appendingPathComponent("complete-summary.json"))
        try JSONEncoder().encode(report).write(to: folder.appendingPathComponent("\(completed.requestID)-report.json"))
        // A file existing is insufficient: a corrupt response must remain retryable.
        try Data("{}".utf8).write(to: folder.appendingPathComponent("\(pendingID)-report.json"))
        try Data("corrupt".utf8).write(to: folder.appendingPathComponent("bad-summary.json"))
        let pending = RoundReportClient.pendingSummaries(in: folder)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.requestID, pendingID)
        XCTAssertEqual(pending.first?.sessionID, sessionID.uuidString)
        XCTAssertEqual(pending.first?.workoutMode, "freestyle")
        let reviews = RoundReportClient.savedReviews(sessionID: sessionID, in: folder)
        XCTAssertEqual(reviews.map(\.round), [1, 2])
        XCTAssertNil(reviews[0].report)
        XCTAssertEqual(reviews[1].report, report)
    }

    func testReviewsNeverCrossSessionsOrGuessLegacySession() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = UUID()
        for (index, identifier) in [session.uuidString, UUID().uuidString, nil].enumerated() {
            let id = UUID().uuidString
            let summary = RoundSummary(requestID: id, language: "en", stance: "orthodox", drillID: "free-boxing-v1",
                                       round: 1, durationS: 180, exchanges: [], sessionID: identifier,
                                       workoutMode: "program", sourceTitle: "Source title \(index)")
            try JSONEncoder().encode(summary).write(to: folder.appendingPathComponent("\(id)-summary.json"))
            try JSONEncoder().encode(report).write(to: folder.appendingPathComponent("\(id)-report.json"))
        }
        let rows = RoundReportClient.savedReviews(sessionID: session, in: folder)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "Source title 0")
        XCTAssertEqual(rows[0].language, "en")
    }

    private var report: RoundReport {
        RoundReport(observation: "One detection", interpretation: "Technique unverified", constraint: "Continue your program",
                    prediction: "Review footage", drill: "Source title", labels: [], models: ["fixture"], latencyMs: 1)
    }
}
