import XCTest
@testable import Coin

@MainActor final class WorkoutActivityInstanceTests: XCTestCase {
    private func sourceBlock(key: String? = nil) -> SessionBlock {
        SessionBlock(kind: .exercise, minutes: 0, roundNumber: nil, drillID: nil, restAfterMinutes: 0,
            sourceTitle: "Weight lifting", sourceInstructions: "Choose your strength work. 3 sets.",
            sourceActivityKey: key, sourceBlockID: "strength-block", sourceItemID: "strength-item",
            repetitionText: "3 sets", completionMode: .manual)
    }
    private func makeStore() -> (TrainingStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (TrainingStore(directory: folder), folder)
    }
    func testChoicePersistsSeparateFromSourceWithImmutableSelectionHistory() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let block = sourceBlock(), template = TrainingTemplate(id: "source", durationMinutes: 0, blocks: [block])
        let id = store.start(template, origin: .synthetic)
        let first = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id))
        XCTAssertNil(first.exerciseKey)
        XCTAssertEqual(first.selectionProvenance, .unchosen)
        XCTAssertEqual(first.measurement.capability, .unsupported)
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "bench_press"))
        let chosen = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id))
        XCTAssertNotEqual(chosen.id, first.id)
        XCTAssertEqual(chosen.selectionProvenance, .userSelected)
        XCTAssertEqual(chosen.measurement.capability, .elapsedOnly)
        XCTAssertEqual(chosen.sourceItemID, "strength-item")
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "squats"))
        let restored = try XCTUnwrap(TrainingStore(directory: folder).data.sessions.first)
        XCTAssertEqual(restored.blocks, template.blocks)
        XCTAssertEqual(restored.activityInstances?.map(\.exerciseKey), [nil, "bench_press", "squats"])
        XCTAssertEqual(restored.activityInstances?.first, first)
        XCTAssertEqual(restored.activityInstances?[1], chosen)
        XCTAssertEqual(restored.activityInstance(blockID: block.id)?.measurement.capability, .repCandidate)
        XCTAssertEqual(restored.exerciseReps?.count, 0)
        XCTAssertEqual(restored.completedBlockIDs.count, 0)
    }
    func testPreparationSlotsRemainDistinctAndInvalidSelectionsDoNotMutate() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let block = SessionBlock(kind: .warmup, minutes: 4, roundNumber: nil, drillID: nil, restAfterMinutes: 0,
            activities: [.init(key: "squats", minutes: 2), .init(key: "lunges", minutes: 2)])
        let id = store.start(TrainingTemplate(id: "prep", durationMinutes: 4, blocks: [block]))
        XCTAssertEqual(store.data.sessions[0].activityInstances?.count, 2)
        XCTAssertEqual(store.data.sessions[0].activityInstance(blockID: block.id, preparationIndex: 1)?.exerciseKey, "lunges")
        XCTAssertFalse(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "bench_press"))
        XCTAssertFalse(store.selectActivity(sessionID: id, blockID: block.id, preparationIndex: 3, exerciseKey: "squats"))
        XCTAssertFalse(store.selectActivity(sessionID: id, blockID: block.id, preparationIndex: 0, exerciseKey: "do whatever <script>"))
        XCTAssertEqual(store.data.sessions[0].activityInstances?.count, 2)
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, preparationIndex: 0, exerciseKey: "box_jumps"))
        XCTAssertEqual(store.data.sessions[0].activityInstance(blockID: block.id, preparationIndex: 0)?.measurement.capability, .elapsedOnly)
        XCTAssertEqual(store.data.sessions[0].activityInstance(blockID: block.id, preparationIndex: 1)?.exerciseKey, "lunges")
    }
    func testOnlyImplementedExactMovementsGetUnvalidatedCandidates() {
        for key in ["squats", "lunges"] {
            let recipe = ActivityMeasurementRecipe.forExercise(key)
            XCTAssertEqual(recipe.capability, .repCandidate)
            XCTAssertEqual(recipe.validationStatus, .unvalidated)
        }
        for key in ["boxing", "shadowboxing"] {
            let recipe = ActivityMeasurementRecipe.forExercise(key)
            XCTAssertEqual(recipe.capability, .exchangeCandidate)
            XCTAssertEqual(recipe.validationStatus, .unvalidated)
        }
        for key in ["box_jumps", "squat_jumps", "burpees", "bench_press", "custom_future_exercise"] {
            let recipe = ActivityMeasurementRecipe.forExercise(key)
            XCTAssertEqual(recipe.id, "session-clock")
            XCTAssertEqual(recipe.capability, .elapsedOnly)
            XCTAssertEqual(recipe.validationStatus, .notApplicable)
        }
        XCTAssertEqual(ActivityMeasurementRecipe.forExercise(nil).capability, .unsupported)
        XCTAssertEqual(ActivityMeasurementRecipe.forExercise("unknown").capability, .unsupported)
        XCTAssertEqual(ActivityMeasurementRecipe.forExercise("frontal_stance").capability, .elapsedOnly)
        XCTAssertEqual(ActivityMeasurementRecipe.forExercise("squats").landmarkGroups.count, 2)
        XCTAssertEqual(ActivityMeasurementRecipe.forExercise("squats").visibilityRule, "any_complete_group")
        XCTAssertEqual(ActivityMeasurementRecipe.forExercise("squats").observationUnit, "rep_candidate")
    }
    func testOpenConditioningStartsUnchosenDespiteBroadSourceBoxingTag() throws {
        let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w2-d1" })
        let block = try XCTUnwrap(lesson.template().blocks.first { $0.activityChoiceFamily == "conditioning" })
        XCTAssertNil(block.sourceActivityKey)
        XCTAssertEqual(block.kind, .boxing)
        let initial = try XCTUnwrap(WorkoutActivityInstance.initial(for: block, at: Date()).first)
        XCTAssertNil(initial.exerciseKey)
        XCTAssertEqual(initial.selectionProvenance, .unchosen)
        XCTAssertEqual(initial.measurement.capability, .unsupported)
        XCTAssertEqual(WorkoutActivityCopy.name("squat_jumps", language: "fr"), "Squats sautés")
        XCTAssertEqual(WorkoutActivityCopy.name("lunges", language: "en"), "Lunges")
        XCTAssertEqual(WorkoutActivityCopy.name("frontal_stance", language: "fr"), "Garde de face")
        XCTAssertFalse(WorkoutActivityRouting.allowsExchange(initial))
    }
    func testExchangeRoutingUsesResolvedMovementInsteadOfBroadBlockKind() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w2-d1" })
        let block = try XCTUnwrap(lesson.template().blocks.first { $0.activityChoiceFamily == "conditioning" })
        let id = store.start(TrainingTemplate(id: "routing", durationMinutes: 0, blocks: [block]))
        XCTAssertFalse(WorkoutActivityRouting.allowsExchange(store.data.sessions[0].activityInstance(blockID: block.id)))
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "burpees"))
        XCTAssertFalse(WorkoutActivityRouting.allowsExchange(store.data.sessions[0].activityInstance(blockID: block.id)))
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "shadowboxing"))
        XCTAssertTrue(WorkoutActivityRouting.allowsExchange(store.data.sessions[0].activityInstance(blockID: block.id)))
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "frontal_stance"))
        XCTAssertFalse(WorkoutActivityRouting.allowsExchange(store.data.sessions[0].activityInstance(blockID: block.id)))
    }
    func testSourceSpecifiedAndUserSelectionAreDistinctEvenForSameExercise() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let block = sourceBlock(key: "squats")
        let id = store.start(TrainingTemplate(id: "source", durationMinutes: 0, blocks: [block]))
        XCTAssertEqual(store.data.sessions[0].activityInstance(blockID: block.id)?.selectionProvenance, .sourceSpecified)
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "squats"))
        XCTAssertEqual(store.data.sessions[0].activityInstance(blockID: block.id)?.selectionProvenance, .userSelected)
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "squats"))
        XCTAssertEqual(store.data.sessions[0].activityInstances?.count, 2)
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: nil))
        XCTAssertEqual(store.data.sessions[0].activityInstance(blockID: block.id)?.selectionProvenance, .unchosen)
        XCTAssertEqual(store.data.sessions[0].blocks[0].sourceActivityKey, "squats")
    }
    func testLegacySessionResumesWithoutInventingUserChoiceAndOldReceiptStaysUnchanged() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let block = sourceBlock(), template = TrainingTemplate(id: "legacy", durationMinutes: 0, blocks: [block])
        let id = store.start(template)
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.file)) as? [String: Any])
        var sessions = try XCTUnwrap(data["sessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "activityInstances"); data["sessions"] = sessions
        try JSONSerialization.data(withJSONObject: data).write(to: store.file)
        let restored = TrainingStore(directory: folder)
        XCTAssertNil(restored.data.sessions[0].activityInstances)
        XCTAssertEqual(restored.resumeOrStart(template), id)
        XCTAssertEqual(restored.data.sessions[0].activityInstance(blockID: block.id)?.selectionProvenance, .unchosen)
        restored.finish(id, reflection: "")
        var receipt = try XCTUnwrap(restored.nextPendingWorkoutCompletion())
        receipt.activityInstances = nil
        let legacyData = try JSONEncoder().encode(receipt)
        let legacyReceipt = try JSONDecoder().decode(WorkoutCompletionReceipt.self, from: legacyData)
        XCTAssertNil(legacyReceipt.payload()["activity_instances"])
    }
    func testCompletionReceiptSnapshotsSelectionLineageWithoutMovementClaims() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let block = sourceBlock(), id = store.start(TrainingTemplate(id: "source", durationMinutes: 0, blocks: [block]))
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "burpees"))
        store.finish(id, reflection: "")
        let receipt = try XCTUnwrap(store.nextPendingWorkoutCompletion())
        XCTAssertFalse(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "squats"))
        let lineage = try XCTUnwrap(receipt.payload()["activity_instances"] as? [[String: Any]])
        XCTAssertEqual(lineage.count, 2)
        XCTAssertEqual(lineage.last?["exercise_key"] as? String, "burpees")
        XCTAssertEqual(lineage.last?["source_item_id"] as? String, "strength-item")
        XCTAssertEqual((lineage.last?["measurement"] as? [String: Any])?["capability"] as? String, "elapsed_only")
        XCTAssertNil(lineage.last?["reps"])
        XCTAssertNil(lineage.last?["success"])
        XCTAssertEqual(receipt.activityInstances, TrainingStore(directory: folder).data.sessions[0].activityInstances)
    }
    func testRepCandidatesJoinOnlyCurrentSupportedInstanceWithoutRelabelingHistory() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let block = sourceBlock(), id = store.start(TrainingTemplate(id: "source", durationMinutes: 0, blocks: [block]))
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "squats"))
        let squat = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id))
        let observedAt = Date()
        store.recordExerciseRep(sessionID: id, blockID: block.id, activityKey: "squats",
            sourceVersion: "mediapipe-squat-angle-v1", activityInstanceID: squat.id, at: observedAt)
        XCTAssertEqual(store.data.sessions[0].exerciseReps?.count, 1)
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "burpees"))
        let burpees = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id))
        for instanceID in [squat.id, burpees.id, UUID()] {
            store.recordExerciseRep(sessionID: id, blockID: block.id, activityKey: "squats",
                sourceVersion: "mediapipe-squat-angle-v1", activityInstanceID: instanceID, at: observedAt.addingTimeInterval(1))
        }
        let restored = try XCTUnwrap(TrainingStore(directory: folder).data.sessions[0].exerciseReps)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].activityInstanceID, squat.id)
        XCTAssertEqual(restored[0].activityKey, "squats")
        XCTAssertNil(store.data.sessions[0].blocks[0].sourceActivityKey)
    }
    func testSourceMappedSquatLungeCandidatesAcceptInstanceAndLegacyCalls() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        for (key, recipe) in [("squats", "mediapipe-squat-angle-v1"), ("lunges", "mediapipe-lunge-angle-v1")] {
            let block = sourceBlock(key: key), id = store.start(TrainingTemplate(id: key, durationMinutes: 0, blocks: [block]))
            let instance = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id))
            XCTAssertEqual(instance.selectionProvenance, .sourceSpecified)
            let observedAt = Date()
            store.recordExerciseRep(sessionID: id, blockID: block.id, activityKey: key,
                sourceVersion: recipe, activityInstanceID: instance.id, at: observedAt)
            store.recordExerciseRep(sessionID: id, blockID: block.id, activityKey: key,
                sourceVersion: "unsupported-version", activityInstanceID: instance.id, at: observedAt.addingTimeInterval(1))
            store.recordExerciseRep(sessionID: id, blockID: block.id, activityKey: key,
                sourceVersion: recipe, at: observedAt.addingTimeInterval(2))
            XCTAssertEqual(store.data.sessions[0].exerciseReps?.count, 2)
            XCTAssertEqual(store.data.sessions[0].exerciseReps?.first?.activityInstanceID, instance.id)
            XCTAssertNil(store.data.sessions[0].exerciseReps?.last?.activityInstanceID)
        }
    }
    func testCustomMovementNameStaysLocalWhileRecipeAbstains() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let block = sourceBlock(), id = store.start(TrainingTemplate(id: "custom", durationMinutes: 0, blocks: [block]))
        XCTAssertFalse(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "custom"))
        XCTAssertTrue(store.selectActivity(sessionID: id, blockID: block.id, exerciseKey: "custom", customName: "  Skater hops  "))
        let selected = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id))
        XCTAssertEqual(selected.customName, "Skater hops")
        XCTAssertEqual(selected.measurement.capability, .elapsedOnly)
        store.finish(id, reflection: "")
        let receipt = try XCTUnwrap(store.nextPendingWorkoutCompletion())
        let payload = try XCTUnwrap((receipt.payload()["activity_instances"] as? [[String: Any]])?.last)
        XCTAssertEqual(payload["exercise_key"] as? String, "custom")
        XCTAssertNil(payload["custom_name"])
    }
}
