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

    func testBasicWeekOneDayOneHasExactAcceptanceContract() throws {
        let template = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d1" }).template()
        let timed = template.blocks.filter { !$0.isManual }
        let manual = template.blocks.filter(\.isManual)
        XCTAssertEqual(template.blocks.count, 24)
        XCTAssertEqual(timed.count, 18)
        XCTAssertEqual(manual.count, 6)
        XCTAssertEqual(timed.compactMap(\.roundNumber), Array(1...18))
        XCTAssertEqual(timed.reduce(0) { $0 + $1.effectiveSeconds }, 2_520)
        XCTAssertEqual(timed.map(\.effectiveRestSeconds).filter { $0 > 0 }, [30, 30, 30])
        XCTAssertEqual(timed.reduce(0) { $0 + $1.effectiveRestSeconds }, 90)
        XCTAssertEqual(template.plannedSeconds, 2_610)
        XCTAssertTrue(manual.allSatisfy { $0.effectiveSeconds == 0 && $0.effectiveRestSeconds == 0 })
    }

    func testEverySourceDayBuildsATraversableRuntimePlan() throws {
        let lessons = WorkoutCatalog.shared.lessons
        var workSegments = 0
        var restSegments = 0
        var timedWork = 0
        var manualWork = 0
        var requiredChoices = 0
        var timedSeconds = 0
        for lesson in lessons {
            let template = lesson.template()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = TrainingStore(directory: folder)
            let sessionID = store.start(template, origin: .synthetic)
            for block in template.blocks {
                let workCount = block.activities?.isEmpty == false ? block.activities?.count ?? 0 : 1
                workSegments += workCount
                if block.effectiveRestSeconds > 0 { restSegments += 1 }
                if block.isManual { manualWork += workCount }
                else {
                    timedWork += workCount
                    XCTAssertGreaterThan(block.effectiveSeconds, 0, block.sourceBlockID ?? lesson.id)
                }
                timedSeconds += block.effectiveSeconds + block.effectiveRestSeconds
                XCTAssertTrue(block.isManual || block.effectiveSeconds > 0, block.sourceBlockID ?? lesson.id)
                if block.effectiveRestSeconds > 0 { XCTAssertGreaterThan(block.effectiveRestSeconds, 0) }
                guard block.activities?.isEmpty != false,
                      let instance = store.data.sessions.first?.activityInstance(blockID: block.id),
                      WorkoutActivityRouting.requiresRuntimeSelection(choiceFamily: block.activityChoiceFamily,
                          sourceActivityKey: block.sourceActivityKey, instance: instance) else { continue }
                requiredChoices += 1
                let choices = WorkoutMovementDefinition.choices(for: block.activityChoiceFamily)
                XCTAssertFalse(choices.isEmpty, block.sourceBlockID ?? lesson.id)
                XCTAssertTrue(store.selectActivity(sessionID: sessionID, blockID: block.id,
                    exerciseKey: try XCTUnwrap(choices.first?.key)))
                let selected = try XCTUnwrap(store.data.sessions.first?.activityInstance(blockID: block.id))
                XCTAssertFalse(WorkoutActivityRouting.requiresRuntimeSelection(choiceFamily: block.activityChoiceFamily,
                    sourceActivityKey: block.sourceActivityKey, instance: selected))
            }
        }
        XCTAssertEqual(lessons.count, 70)
        XCTAssertEqual(workSegments, 1_236)
        XCTAssertEqual(restSegments, 205)
        XCTAssertEqual(timedWork, 734)
        XCTAssertEqual(manualWork, 502)
        XCTAssertEqual(requiredChoices, 77)
        XCTAssertEqual(timedSeconds, 100_935)
    }

    func testBasicWeekOneDayThreeMixedBlockExpandsExactPrescriptions() throws {
        let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d3" })
        let source = try XCTUnwrap(lesson.blocks.first { $0.id == "basic-w1-d3-p5-s6-1" })
        let blocks = lesson.template().blocks.filter { $0.sourceBlockID == source.id }
        XCTAssertEqual(blocks.count, 15)

        let bag = Array(blocks.prefix(7))
        XCTAssertEqual(bag.map(\.sourceItemID), ["p5-b27", "p5-b29", "p5-b31", "p5-b32",
            "p5-b34", "p5-b36", "p5-b38"].map(Optional.some))
        XCTAssertEqual(bag.map(\.effectiveSeconds), Array(repeating: 180, count: 7))
        XCTAssertEqual(bag.map(\.effectiveRestSeconds), Array(repeating: 60, count: 6) + [0])
        XCTAssertEqual(bag.last?.sourceDemoURLs, ["https://youtu.be/oYG9JVu3k38?si=e81bxKdTvx3vyWoD&t=17"])

        let tennis = Array(blocks[7..<10])
        XCTAssertEqual(tennis.map(\.sourceItemID), Array(repeating: Optional("p5-b41"), count: 3))
        XCTAssertEqual(tennis.map(\.effectiveSeconds), [60, 60, 60])
        XCTAssertEqual(tennis.map(\.effectiveRestSeconds), [0, 0, 0])
        XCTAssertTrue(tennis.allSatisfy { $0.sourceInstructions == source.sourceItems?[10].text })

        let dumbbells = blocks[10]
        XCTAssertEqual(dumbbells.sourceItemID, "p5-b43")
        XCTAssertTrue(dumbbells.isManual)
        XCTAssertEqual(dumbbells.effectiveSeconds, 0)
        XCTAssertEqual(dumbbells.sourceDemoURLs, ["https://www.youtube.com/shorts/-NkpM5DYF2Y"])

        let strength = Array(blocks.suffix(4))
        XCTAssertEqual(strength.map(\.sourceItemID), Array(repeating: Optional("p5-b45"), count: 4))
        XCTAssertEqual(strength.map(\.sourceTitle), ["parallel bar dips", "pull-ups",
            "jumping squat lunges", "hanging leg raises"].map(Optional.some))
        XCTAssertTrue(strength.allSatisfy { $0.isManual && $0.effectiveSeconds == 0
            && $0.repetitionText == "1 set of max" && $0.sourceInstructions == source.sourceItems?[12].text })
        XCTAssertEqual(strength.map(\.effectiveRestSeconds), [60, 60, 60, 0])
        XCTAssertEqual(strength.map(\.sourceDemoURLs), source.sourceItems?[12].demoURLs?.map { [$0] })
    }

    func testBasicWeekOneDayThreeMixedBlockFailsClosedWhenExactSourceChanges() throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { block in
                var items = block["sourceItems"] as! [[String: Any]]
                items[10]["text"] = "Changed tennis prescription"
                block["sourceItems"] = items
                let text = items.map { $0["text"] as! String }.joined(separator: "\n")
                block["instructions"] = text
                block["sourceText"] = text
            },
            { block in
                var items = block["sourceItems"] as! [[String: Any]]
                items[12]["demoURLs"] = ["https://example.org/changed"]
                block["sourceItems"] = items
            },
        ]
        for change in changes {
            let lesson = try roundSequenceFixture("basic-w1-d3-p5-s6-1", change)
            let source = try XCTUnwrap(lesson.blocks.first)
            XCTAssertNil(source.reviewedMixedDaySteps)
            let blocks = lesson.template().blocks
            XCTAssertEqual(blocks.count, 1)
            XCTAssertTrue(try XCTUnwrap(blocks.first).isManual)
            XCTAssertEqual(blocks.first?.effectiveSeconds, 0)
            XCTAssertNil(blocks.first?.sourceItemID)
        }
    }

    func testReviewedBagIntervalsKeepExactFocusAndManualUntimedExercises() throws {
        let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "competitive-w4-d3" })
        let source = try XCTUnwrap(lesson.blocks.first { $0.id == "competitive-w4-d3-p31-s4-1" })
        let steps = try XCTUnwrap(source.reviewedBagExerciseIntervals)
        let blocks = lesson.template().blocks.filter { $0.sourceBlockID == source.id }
        let rounds = blocks.filter { !$0.isManual }
        let exercises = blocks.filter(\.isManual)

        XCTAssertEqual(steps.count, 10)
        XCTAssertEqual(blocks.count, 19)
        XCTAssertEqual(rounds.count, 10)
        XCTAssertEqual(exercises.count, 9)
        XCTAssertEqual(rounds.map(\.effectiveSeconds), Array(repeating: 120, count: 10))
        XCTAssertEqual(rounds.map(\.effectiveRestSeconds), Array(repeating: 0, count: 10))
        XCTAssertEqual(rounds.map(\.sourceItemID),
            ["p31-b17", "p31-b18", "p31-b19", "p31-b20", "p31-b21",
             "p31-b22", "p31-b24", "p31-b27", "p31-b29", "p31-b31"].map(Optional.some))
        XCTAssertEqual(rounds.map(\.sourceTitle), steps.map { Optional($0.focusText) })
        XCTAssertEqual(rounds[6].sourceTitle,
            "HOOK BODY - HOOK BODY - HOOK HEAD — HOOK BODY -HOOK BODY - UPPERCUT\nHEAD")
        XCTAssertEqual(rounds[6].sourceDemoURLs, ["https://youtube.com/shorts/KLT_62jjjqs"])
        XCTAssertTrue(rounds.allSatisfy { $0.kind == .boxing && $0.sourceActivityKey == "bag_work" })
        XCTAssertTrue(exercises.allSatisfy {
            $0.kind == .exercise && $0.effectiveSeconds == 0 && $0.effectiveRestSeconds == 0 &&
            $0.sourceItemID == "p31-b16" &&
            $0.sourceTitle == "(add 10 push-ups and 10 squats during rest periods)" &&
            $0.repetitionText == "10 push-ups + 10 squats"
        })
        XCTAssertEqual(blocks.last?.sourceItemID, "p31-b31")
        XCTAssertFalse(try XCTUnwrap(blocks.last).isManual)
        XCTAssertEqual(templateCounts(blocks).pushups, 90)
        XCTAssertEqual(templateCounts(blocks).squats, 90)
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.effectiveSeconds + $1.effectiveRestSeconds }, 1_200)
    }

    func testReviewedBagIntervalsFailClosedOnAnyExactSourceDrift() throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { block in
                var items = block["sourceItems"] as! [[String: Any]]
                items[9]["text"] = "CHANGED WRAPPED LINE"
                block["sourceItems"] = items
                let text = items.map { $0["text"] as! String }.joined(separator: "\n")
                block["instructions"] = text
                block["sourceText"] = text
            },
            { $0["title"] = "BAG WORK (10 ROUNDS)" },
            { $0["kind"] = "boxing" },
        ]
        for change in changes {
            let lesson = try roundSequenceFixture("competitive-w4-d3-p31-s4-1", change)
            let source = try XCTUnwrap(lesson.blocks.first)
            XCTAssertNil(source.reviewedBagExerciseIntervals)
            let blocks = lesson.template().blocks
            XCTAssertEqual(blocks.count, 1)
            XCTAssertTrue(try XCTUnwrap(blocks.first).isManual)
            XCTAssertNil(blocks.first?.sourceItemID)
        }
    }

    private func templateCounts(_ blocks: [SessionBlock]) -> (pushups: Int, squats: Int) {
        let intervals = blocks.filter { $0.isManual && $0.sourceItemID == "p31-b16" }.count
        return (intervals * 10, intervals * 10)
    }

    func testReviewedEnduranceDaysExpandIntoExactThreeCircuitClock() throws {
        let expectedExercises = [
            "Push-Up Shuttle", "Squat With Med Ball Throws", "Rolls", "Plate Punches",
            "Side Jumps", "Plank", "Landmine Punches", "Boxing Steps With Weights",
            "Wall Sit", "Barbell Push-Outs",
        ]
        for lessonID in ["competitive-w2-d6", "competitive-w4-d6"] {
            let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == lessonID })
            let source = try XCTUnwrap(lesson.blocks.first)
            let blocks = lesson.template().blocks
            XCTAssertEqual(blocks.count, 30)
            XCTAssertEqual(blocks.map(\.sourceTitle), Array(repeating: expectedExercises, count: 3).flatMap { $0 })
            XCTAssertEqual(blocks.map(\.effectiveSeconds), Array(repeating: 60, count: 30))
            XCTAssertEqual(blocks.map(\.effectiveRestSeconds),
                Array(repeating: Array(repeating: 30, count: 9) + [120], count: 2).flatMap { $0 }
                    + Array(repeating: 30, count: 9) + [0])
            XCTAssertEqual(blocks.map(\.sourceBlockID), Array(repeating: source.id, count: 30))
            XCTAssertEqual(Set(blocks.compactMap(\.sourceItemID)).count, 10)
            XCTAssertTrue(blocks.allSatisfy { $0.sourceInstructions == source.instructions })
            XCTAssertTrue(blocks.allSatisfy { $0.sourceDemoURLs == source.demoURLs })
            XCTAssertTrue(blocks.allSatisfy { !$0.isManual })
            XCTAssertEqual(lesson.template().plannedSeconds, 2_850)
        }
    }

    func testChangedEndurancePrescriptionFallsBackToOneManualSourceBlock() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "WorkoutCatalog", withExtension: "json"))
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: "3 CIRCUITS, 10 EXERCISES EACH. WORK FOR 1 MINUTE, REST FOR",
                                         with: "3 CIRCUITS, 10 EXERCISES EACH. CHANGED SOURCE")
        let catalog = try WorkoutCatalog.load(Data(text.utf8))
        let lesson = try XCTUnwrap(catalog.lessons.first { $0.id == "competitive-w2-d6" })
        let blocks = lesson.template().blocks
        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(try XCTUnwrap(blocks.first).isManual)
        XCTAssertEqual(blocks.first?.effectiveSeconds, 0)
    }

    func testGenericSourceSlotsRequireConcreteRuntimeMovement() throws {
        let source = WorkoutCatalog.shared.lessons.flatMap(\.blocks)
        let warmups = source.filter { $0.title == "DYNAMIC WARM-UP:" && $0.instructions == $0.title }
        let stretches = source.filter { $0.title == "STRETCHES" && $0.instructions == $0.title }
        XCTAssertEqual(warmups.count, 50)
        XCTAssertEqual(stretches.count, 21)
        for block in warmups + stretches {
            XCTAssertEqual(block.reviewedChoiceFamily, "mobility")
            let sessionBlock = try XCTUnwrap(WorkoutCatalog.shared.lessons
                .first { $0.blocks.contains { $0.id == block.id } }?.template().blocks
                .first { $0.sourceBlockID == block.id })
            let instance = try XCTUnwrap(WorkoutActivityInstance.initial(for: sessionBlock, at: Date()).first)
            XCTAssertTrue(WorkoutActivityRouting.requiresRuntimeSelection(choiceFamily: sessionBlock.activityChoiceFamily,
                sourceActivityKey: sessionBlock.sourceActivityKey, instance: instance))
        }
        let fourMinute = source.filter { $0.title == "CONDITIONING DRILL (4 MINUTES)" }
        XCTAssertEqual(fourMinute.count, 2)
        XCTAssertTrue(fourMinute.allSatisfy { $0.completion == .timed && $0.rounds == 1 && $0.durationSeconds == 240 })
        let bag = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d5" }?
            .template().blocks.first { $0.sourceBlockID == "basic-w1-d5-p7-s6-4" })
        XCTAssertEqual(bag.sourceActivityKey, "bag_work")
        XCTAssertEqual(WorkoutActivityInstance.initial(for: bag, at: Date()).first?.measurement.capability, .elapsedOnly)
    }

    func testMixedSourcePrescriptionsKeepSeparateClocksAndNoFalseExchangeTracking() throws {
        let basic = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d5" })
        let blocks = basic.template().blocks
        let bag = blocks.filter { $0.sourceBlockID == "basic-w1-d5-p7-s6-1" }
        XCTAssertEqual(bag.count, 6)
        XCTAssertEqual(bag.map(\.effectiveSeconds), Array(repeating: 180, count: 6))
        XCTAssertEqual(bag.map(\.effectiveRestSeconds), Array(repeating: 0, count: 6))
        XCTAssertTrue(bag.allSatisfy { $0.sourceItemID == nil && $0.kind == .boxing })

        let bands = blocks.filter { $0.sourceBlockID == "basic-w1-d5-p7-s6-2" }
        XCTAssertEqual(bands.count, 6)
        XCTAssertEqual(bands.map(\.effectiveSeconds), Array(repeating: 60, count: 6))
        XCTAssertEqual(bands.map(\.effectiveRestSeconds), [20, 20, 20, 20, 20, 0])
        XCTAssertTrue(bands.allSatisfy { $0.kind == .exercise && $0.drillID == nil })
        for block in bands {
            let instance = try XCTUnwrap(WorkoutActivityInstance.initial(for: block, at: Date()).first)
            XCTAssertFalse(WorkoutActivityRouting.allowsExchange(instance))
        }
        for suffix in ["3", "4"] {
            let manual = try XCTUnwrap(blocks.first { $0.sourceBlockID == "basic-w1-d5-p7-s6-\(suffix)" })
            XCTAssertTrue(manual.isManual)
            XCTAssertEqual(manual.kind, .exercise)
            XCTAssertEqual(manual.effectiveSeconds, 0)
            XCTAssertFalse(WorkoutActivityRouting.allowsExchange(
                WorkoutActivityInstance.initial(for: manual, at: Date()).first))
        }

        let competitive = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "competitive-w1-d1" })
        let stages = competitive.template().blocks
        let circuit = try XCTUnwrap(stages.first { $0.sourceBlockID == "competitive-w1-d1-p5-s3-3" })
        XCTAssertTrue(circuit.isManual)
        XCTAssertEqual(circuit.kind, .exercise)
        let rotation = try XCTUnwrap(stages.first { $0.sourceBlockID == "competitive-w1-d1-p5-s3-4" })
        XCTAssertEqual(rotation.effectiveSeconds, 180)
        XCTAssertEqual(rotation.kind, .exercise)
        XCTAssertNil(rotation.drillID)
        XCTAssertFalse(WorkoutActivityRouting.allowsExchange(
            WorkoutActivityInstance.initial(for: rotation, at: Date()).first))
    }

    func testExactJumpSquatPrescriptionsGetClockOnlyMovementLineage() throws {
        let ids: Set<String> = ["basic-w1-d1-p3-s6-2", "basic-w2-d1-p10-s5-2",
            "basic-w2-d5-p14-s3-2", "basic-w3-d1-p17-s5-2", "basic-w3-d5-p21-s3-2",
            "basic-w4-d1-p24-s5-2", "basic-w4-d5-p28-s3-2", "basic-w5-d1-p31-s5-2"]
        let blocks = WorkoutCatalog.shared.lessons.flatMap { $0.template().blocks }
            .filter { ids.contains($0.sourceBlockID ?? "") }
        XCTAssertEqual(blocks.count, ids.count)
        for block in blocks {
            XCTAssertEqual(block.sourceActivityKey, "squat_jumps")
            XCTAssertNotNil(block.sourceItemID)
            XCTAssertTrue(block.isManual)
            XCTAssertEqual(block.effectiveSeconds, 0)
            XCTAssertTrue(["10 JUMP SQUATS", "12 JUMP SQUATS"].contains(block.sourceInstructions ?? ""))
            let instance = try XCTUnwrap(WorkoutActivityInstance.initial(for: block, at: Date()).first)
            XCTAssertEqual(instance.selectionProvenance, .sourceSpecified)
            XCTAssertEqual(instance.measurement.capability, .elapsedOnly)
            XCTAssertEqual(instance.sourceBlockID, block.sourceBlockID)
        }

        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            try XCTUnwrap(Bundle.main.url(forResource: "WorkoutCatalog", withExtension: "json")))) as? [String: Any])
        var lessons = try XCTUnwrap(raw["workouts"] as? [[String: Any]])
        let lessonIndex = try XCTUnwrap(lessons.firstIndex { $0["id"] as? String == "basic-w1-d1" })
        var sourceBlocks = try XCTUnwrap(lessons[lessonIndex]["blocks"] as? [[String: Any]])
        let blockIndex = try XCTUnwrap(sourceBlocks.firstIndex { $0["id"] as? String == "basic-w1-d1-p3-s6-2" })
        sourceBlocks[blockIndex]["instructions"] = "12 JUMP SQUATS AND BURPEES"
        lessons[lessonIndex]["blocks"] = sourceBlocks
        raw["workouts"] = lessons
        let changed = try WorkoutCatalog.load(JSONSerialization.data(withJSONObject: raw))
        let changedBlock = try XCTUnwrap(changed.lessons.first { $0.id == "basic-w1-d1" }?
            .template().blocks.first { $0.sourceBlockID == "basic-w1-d1-p3-s6-2" })
        XCTAssertNil(changedBlock.sourceActivityKey)
    }

    func testExactDayOneFrontalStanceDoesNotClaimPunchExchanges() throws {
        let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d1" })
        let ids: Set<String> = ["basic-w1-d1-p3-s3-1", "basic-w1-d1-p3-s5-1", "basic-w1-d1-p3-s7-1"]
        let stance = lesson.template().blocks.filter { ids.contains($0.sourceBlockID ?? "") }
        XCTAssertEqual(stance.count, 6)
        for block in stance {
            XCTAssertEqual(block.sourceActivityKey, "frontal_stance")
            let instance = try XCTUnwrap(WorkoutActivityInstance.initial(for: block, at: Date()).first)
            XCTAssertEqual(instance.selectionProvenance, .sourceSpecified)
            XCTAssertEqual(instance.measurement.capability, .elapsedOnly)
            XCTAssertFalse(WorkoutActivityRouting.allowsExchange(instance))
        }
        let punching = try XCTUnwrap(lesson.template().blocks.first {
            $0.sourceBlockID == "basic-w1-d1-p3-s4-1" })
        XCTAssertTrue(WorkoutActivityRouting.allowsExchange(
            WorkoutActivityInstance.initial(for: punching, at: Date()).first))
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
            XCTAssertEqual(block.sourceActivityKey, index == 0 ? "squats" : nil)
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
        var roundSections = 0
        var roundItems = 0
        var circuitSections = 0
        var circuitItems = 0
        for lesson in WorkoutCatalog.shared.lessons {
            let blocks = lesson.template().blocks
            for source in lesson.blocks {
                let mapped = blocks.filter { $0.sourceBlockID == source.id }
                if mapped.count == 1, mapped.first?.sourceActivityKey == "squat_jumps" {
                    XCTAssertEqual(mapped.first?.sourceItemID, source.sourceItems?.first?.id)
                    XCTAssertEqual(mapped.first?.sourceInstructions, source.instructions)
                } else if source.reviewedEnduranceCircuitSteps != nil {
                    circuitSections += 1
                    circuitItems += mapped.count
                    XCTAssertTrue(mapped.allSatisfy { $0.sourceItemID != nil && !$0.isManual })
                } else if mapped.contains(where: { $0.sourceItemID != nil }) {
                    if source.completion == .manual {
                        expandedSections += 1
                        expandedItems += mapped.count
                    } else {
                        roundSections += 1
                        roundItems += mapped.count
                    }
                    XCTAssertTrue(mapped.allSatisfy { $0.sourceItemID != nil })
                } else {
                    XCTAssertEqual(mapped.count, source.completion == .timed ? (source.rounds ?? 1) : 1)
                    XCTAssertTrue(mapped.allSatisfy { $0.sourceInstructions == source.instructions })
                }
            }
        }
        XCTAssertEqual(expandedSections, 30)
        XCTAssertEqual(expandedItems, 278)
        XCTAssertEqual(roundSections, 5)
        XCTAssertEqual(roundItems, 25)
        XCTAssertEqual(circuitSections, 2)
        XCTAssertEqual(circuitItems, 60)
    }

    func testOnlyFourReviewedSourceItemsEnableExistingRepCandidates() throws {
        let expected: [String: String] = [
            "basic-w1-d6-p8-s1-1:p8-b6": "squats",
            "competitive-w1-d2-p6-s8-1:p6-b50": "lunges",
            "competitive-w3-d2-p22-s8-1:p22-b38": "lunges",
            "competitive-w4-d2-p30-s9-1:p30-b53": "lunges",
        ]
        let active = WorkoutCatalog.shared.lessons.flatMap { $0.template().blocks }
            .compactMap { block -> (String, String)? in
                guard let section = block.sourceBlockID, let item = block.sourceItemID,
                      let key = block.sourceActivityKey,
                      ActivityMeasurementRecipe.forExercise(key).capability == .repCandidate else { return nil }
                return (section + ":" + item, key)
            }
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: active), expected)
        XCTAssertEqual(active.count, expected.count)
        let excluded = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d1" })
        let jump = try XCTUnwrap(excluded.blocks.first { $0.id == "basic-w1-d1-p3-s6-2" })
        XCTAssertTrue(try XCTUnwrap(jump.sourceItems).contains { $0.text == "12 JUMP SQUATS" })
        XCTAssertTrue(excluded.template().blocks.filter { $0.sourceBlockID == jump.id }
            .allSatisfy { $0.sourceActivityKey == "squat_jumps" &&
                ActivityMeasurementRecipe.forExercise($0.sourceActivityKey).capability == .elapsedOnly })
    }

    func testOnlyGenericConditioningSectionsOfferRuntimeMovementChoice() throws {
        let expected: Set<String> = ["basic-w2-d1-p10-s7-2", "basic-w2-d5-p14-s6-2",
            "basic-w3-d1-p17-s7-2", "basic-w3-d5-p21-s6-2", "basic-w4-d1-p24-s7-2"]
        let offered = WorkoutCatalog.shared.lessons.flatMap { $0.template().blocks }
            .filter { $0.activityChoiceFamily == "conditioning" }
        XCTAssertEqual(Set(offered.compactMap(\.sourceBlockID)), expected)
        XCTAssertTrue(offered.allSatisfy { $0.sourceActivityKey == nil })
        let mixed = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d1" })
        XCTAssertTrue(mixed.template().blocks.filter { $0.sourceBlockID == "basic-w1-d1-p3-s9-2" }
            .allSatisfy { $0.activityChoiceFamily == nil })
    }

    func testReviewedPadRoundsUseExactOrderedFocusAndKeepPrescription() throws {
        for week in 1...5 {
            let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "competitive-w\(week)-d4" })
            let source = try XCTUnwrap(lesson.blocks.first { $0.title == "VIRTUAL PAD WORK (5 ROUNDS OF 3 MINUTES)" })
            let items = Array(try XCTUnwrap(source.sourceItems).dropFirst())
            let template = lesson.template()
            let rounds = template.blocks.filter { $0.sourceBlockID == source.id }
            XCTAssertEqual(rounds.count, 5)
            XCTAssertEqual(rounds.map(\.sourceItemID), items.map { Optional($0.id) })
            XCTAssertEqual(rounds.map(\.sourceTitle), items.map { Optional($0.text) })
            XCTAssertEqual(rounds.map(\.effectiveSeconds), Array(repeating: 180, count: 5))
            XCTAssertEqual(rounds.map(\.effectiveRestSeconds), [0, 0, 0, 0, 0])
            let firstNumber = try XCTUnwrap(rounds.first?.roundNumber)
            XCTAssertEqual(rounds.map(\.roundNumber), (firstNumber..<(firstNumber + 5)).map(Optional.some))
            for (round, item) in zip(rounds, items) {
                XCTAssertEqual(round.sourceInstructions, source.title + "\n" + item.text)
                XCTAssertEqual(round.sourceURL, source.sourceURL ?? lesson.sourceURL)
                XCTAssertEqual(round.sourceDemoURLs, source.sourceItems?.first?.demoURLs)
                XCTAssertEqual(round.drillID, source.drillID)
                XCTAssertNil(round.sourceActivityKey)
                XCTAssertFalse(round.isManual)
            }
            XCTAssertEqual(template.sourceVersion, lesson.sourceSHA256)
        }
    }

    func testReviewedManualRoundSequencesUseExactClocksRestsAndLineage() throws {
        let expected: [(lesson: String, block: String, seconds: [Int], rests: [Int], itemIDs: [String])] = [
            ("competitive-w5-d1", "competitive-w5-d1-p37-s3-1",
             [180, 180, 180], [60, 60, 0], ["p37-b8", "p37-b9", "p37-b10"]),
            ("competitive-w5-d2", "competitive-w5-d2-p38-s5-1",
             [60, 60, 60], [30, 30, 0], ["p38-b19", "p38-b20", "p38-b21"]),
            ("basic-w2-d2", "basic-w2-d2-p11-s8-1",
             Array(repeating: 180, count: 5), Array(repeating: 0, count: 5),
             ["p11-b25", "p11-b27", "p11-b29", "p11-b30", "p11-b32"]),
            ("basic-w3-d2", "basic-w3-d2-p18-s8-1",
             Array(repeating: 180, count: 5), Array(repeating: 0, count: 5),
             ["p18-b26", "p18-b27", "p18-b28", "p18-b30", "p18-b31"]),
            ("basic-w4-d2", "basic-w4-d2-p25-s7-1",
             Array(repeating: 180, count: 5), Array(repeating: 0, count: 5),
             ["p25-b22", "p25-b24", "p25-b25", "p25-b27", "p25-b28"]),
            ("basic-w5-d2", "basic-w5-d2-p32-s7-1",
             Array(repeating: 180, count: 5), Array(repeating: 0, count: 5),
             ["p32-b22", "p32-b23", "p32-b24", "p32-b25", "p32-b27"]),
        ]
        for value in expected {
            let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == value.lesson })
            let source = try XCTUnwrap(lesson.blocks.first { $0.id == value.block })
            let steps = try XCTUnwrap(source.reviewedRoundSequence)
            let rounds = lesson.template().blocks.filter { $0.sourceBlockID == value.block }
            XCTAssertEqual(rounds.map(\.effectiveSeconds), value.seconds, value.block)
            XCTAssertEqual(rounds.map(\.effectiveRestSeconds), value.rests, value.block)
            XCTAssertEqual(rounds.map(\.sourceItemID), value.itemIDs.map(Optional.some), value.block)
            XCTAssertEqual(rounds.map(\.sourceTitle), steps.map { Optional($0.focusText) }, value.block)
            XCTAssertTrue(rounds.allSatisfy { !$0.isManual && $0.drillID == source.drillID })
            for (round, step) in zip(rounds, steps) {
                XCTAssertEqual(round.sourceInstructions, source.title + "\n" + step.focusText)
                let expectedDemos = source.sourceItems?.filter { step.sourceItemIDs.contains($0.id) }
                    .flatMap { $0.demoURLs ?? [] } ?? []
                XCTAssertEqual(round.sourceDemoURLs, expectedDemos)
            }
        }
    }

    func testReviewedManualRoundSequencesFailClosedWhenSourceChanges() throws {
        let ids = ["competitive-w5-d1-p37-s3-1", "competitive-w5-d2-p38-s5-1",
                   "basic-w2-d2-p11-s8-1", "basic-w3-d2-p18-s8-1",
                   "basic-w4-d2-p25-s7-1", "basic-w5-d2-p32-s7-1"]
        for id in ids {
            let lesson = try roundSequenceFixture(id) { block in
                var items = block["sourceItems"] as! [[String: Any]]
                items[items.count - 1]["text"] = "CHANGED SOURCE"
                block["sourceItems"] = items
                let text = items.map { $0["text"] as! String }.joined(separator: "\n")
                block["instructions"] = text
                block["sourceText"] = text
            }
            let source = try XCTUnwrap(lesson.blocks.first)
            XCTAssertNil(source.reviewedRoundSequence, id)
            let blocks = lesson.template().blocks
            XCTAssertEqual(blocks.count, 1, id)
            XCTAssertTrue(try XCTUnwrap(blocks.first).isManual, id)
            XCTAssertNil(blocks.first?.sourceItemID, id)
        }
    }

    func testChangedOrUnreviewedPadSnapshotsStayWhole() throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["id"] = "unreviewed-pad-list" },
            { $0["durationSeconds"] = 120 },
            { $0["rounds"] = 4 },
            { $0["kind"] = "exercise" },
            { $0["sourceText"] = "Different extraction" },
            { block in
                var items = block["sourceItems"] as! [[String: Any]]
                items.removeLast()
                block["sourceItems"] = items
            },
            { block in
                var items = block["sourceItems"] as! [[String: Any]]
                items[1]["id"] = items[2]["id"]
                block["sourceItems"] = items
            },
            { block in
                var items = block["sourceItems"] as! [[String: Any]]
                items[1]["text"] = "CHANGED INSTRUCTION"
                block["sourceItems"] = items
                let text = items.map { $0["text"] as! String }.joined(separator: "\n")
                block["instructions"] = text
                block["sourceText"] = text
            },
        ]
        for change in changes {
            let lesson = try padFixture(change)
            let source = try XCTUnwrap(lesson.blocks.first)
            let rounds = lesson.template().blocks
            XCTAssertEqual(rounds.count, source.rounds)
            XCTAssertTrue(rounds.allSatisfy { $0.sourceItemID == nil && $0.sourceTitle == source.title
                && $0.sourceInstructions == source.instructions && $0.sourceDemoURLs == source.demoURLs })
        }
    }

    func testPadRoundRestAndSharedDemoContextArePreserved() throws {
        let lesson = try padFixture { block in
            block["restSeconds"] = 25
            var items = block["sourceItems"] as! [[String: Any]]
            let headingURL = (items[0]["demoURLs"] as! [String])[0]
            items[1]["demoURLs"] = [headingURL, "https://example.org/item-demo"]
            block["sourceItems"] = items
        }
        let rounds = lesson.template().blocks
        XCTAssertEqual(rounds.map(\.effectiveRestSeconds), [25, 25, 25, 25, 0])
        XCTAssertEqual(lesson.template().plannedSeconds, 1_000)
        XCTAssertEqual(rounds.first?.sourceDemoURLs, ["https://youtu.be/zicFYNzPStI", "https://example.org/item-demo"])
        let restored = try JSONDecoder().decode([SessionBlock].self, from: JSONEncoder().encode(rounds))
        XCTAssertEqual(restored.map(\.sourceItemID), rounds.map(\.sourceItemID))
        XCTAssertEqual(restored.map(\.sourceInstructions), rounds.map(\.sourceInstructions))
    }

    private func padFixture(_ change: (inout [String: Any]) -> Void) throws -> WorkoutLesson {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "WorkoutCatalog", withExtension: "json"))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var lesson = try XCTUnwrap((catalog["workouts"] as? [[String: Any]])?.first { $0["id"] as? String == "competitive-w1-d4" })
        var block = try XCTUnwrap((lesson["blocks"] as? [[String: Any]])?.first { $0["id"] as? String == "competitive-w1-d4-p8-s4-1" })
        change(&block)
        lesson["blocks"] = [block]
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "workouts": [lesson]])
        return try XCTUnwrap(WorkoutCatalog.load(data).lessons.first)
    }

    private func roundSequenceFixture(_ blockID: String,
                                      _ change: (inout [String: Any]) -> Void) throws -> WorkoutLesson {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "WorkoutCatalog", withExtension: "json"))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var lesson = try XCTUnwrap((catalog["workouts"] as? [[String: Any]])?.first {
            (($0["blocks"] as? [[String: Any]]) ?? []).contains { $0["id"] as? String == blockID }
        })
        var block = try XCTUnwrap((lesson["blocks"] as? [[String: Any]])?.first { $0["id"] as? String == blockID })
        change(&block)
        lesson["blocks"] = [block]
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "workouts": [lesson]])
        return try XCTUnwrap(WorkoutCatalog.load(data).lessons.first)
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
