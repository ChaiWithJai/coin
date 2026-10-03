import XCTest
@testable import Coin

@MainActor final class WorkoutActivityIntervalTests: XCTestCase {
    private func manualBlock() -> SessionBlock {
        SessionBlock(kind: .exercise, minutes: 0, roundNumber: nil, drillID: nil,
            restAfterMinutes: 0, sourceTitle: "Strength", completionMode: .manual)
    }
    func testChoiceChangeClosesPriorInstanceAndRelaunchDoesNotDoubleCount() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(directory: folder), block = manualBlock()
        let sessionID = store.start(TrainingTemplate(id: "manual", durationMinutes: 0, blocks: [block]))
        XCTAssertTrue(store.selectActivity(sessionID: sessionID, blockID: block.id, exerciseKey: "squats"))
        let squat = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id))
        XCTAssertTrue(store.selectActivity(sessionID: sessionID, blockID: block.id, exerciseKey: "bench_press"))
        let press = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id))
        XCTAssertTrue(store.recordActivityInterval(sessionID: sessionID, blockID: block.id,
            activityInstanceID: squat.id, cumulativeElapsedSeconds: 20, exitReason: .choiceChanged))
        let restored = TrainingStore(directory: folder)
        XCTAssertFalse(restored.recordActivityInterval(sessionID: sessionID, blockID: block.id,
            activityInstanceID: squat.id, cumulativeElapsedSeconds: 20, exitReason: .choiceChanged))
        XCTAssertFalse(restored.recordActivityInterval(sessionID: sessionID, blockID: block.id,
            activityInstanceID: press.id, cumulativeElapsedSeconds: 19, exitReason: .paused))
        XCTAssertTrue(restored.recordActivityInterval(sessionID: sessionID, blockID: block.id,
            activityInstanceID: press.id, cumulativeElapsedSeconds: 35, exitReason: .paused))
        // An hour of paused wall time contributes only the five supplied timer seconds.
        XCTAssertTrue(restored.recordActivityInterval(sessionID: sessionID, blockID: block.id,
            activityInstanceID: press.id, cumulativeElapsedSeconds: 40, exitReason: .sessionFinished,
            at: Date().addingTimeInterval(3600)))
        let session = try XCTUnwrap(TrainingStore(directory: folder).data.sessions.first)
        XCTAssertEqual(session.activityElapsedSeconds(instanceID: squat.id), 20)
        XCTAssertEqual(session.activityElapsedSeconds(instanceID: press.id), 20)
        XCTAssertEqual(session.activityIntervals?.map(\.elapsedSeconds), [20, 15, 5])
        XCTAssertEqual(session.activityIntervals?.map(\.startElapsedSeconds), [0, 20, 35])
    }
    func testSlotsAreSeparateAndInvalidAttributionIsRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(directory: folder)
        let block = SessionBlock(kind: .warmup, minutes: 2, roundNumber: nil, drillID: nil, restAfterMinutes: 0,
            activities: [.init(key: "squats", minutes: 1), .init(key: "lunges", minutes: 1)])
        let id = store.start(TrainingTemplate(id: "prep", durationMinutes: 2, blocks: [block]))
        let first = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id, preparationIndex: 0))
        let second = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id, preparationIndex: 1))
        XCTAssertFalse(store.recordActivityInterval(sessionID: id, blockID: block.id, preparationIndex: 1,
            activityInstanceID: first.id, cumulativeElapsedSeconds: 10, exitReason: .segmentEnded))
        XCTAssertFalse(store.recordActivityInterval(sessionID: id, blockID: block.id, preparationIndex: 0,
            activityInstanceID: first.id, cumulativeElapsedSeconds: 61, exitReason: .segmentEnded))
        XCTAssertTrue(store.recordActivityInterval(sessionID: id, blockID: block.id, preparationIndex: 0,
            activityInstanceID: first.id, cumulativeElapsedSeconds: 20, exitReason: .segmentEnded))
        XCTAssertTrue(store.recordActivityInterval(sessionID: id, blockID: block.id, preparationIndex: 1,
            activityInstanceID: second.id, cumulativeElapsedSeconds: 10, exitReason: .segmentEnded))
        XCTAssertEqual(store.data.sessions[0].activityIntervals?.map(\.elapsedSeconds), [20, 10])
    }
    func testLegacyFirstBoundaryDoesNotAttributePreUpgradeTimerTime() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(directory: folder), block = manualBlock()
        let id = store.start(TrainingTemplate(id: "legacy", durationMinutes: 0, blocks: [block]))
        let instance = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id))
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.file)) as? [String: Any])
        var sessions = try XCTUnwrap(data["sessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "activityIntervals"); data["sessions"] = sessions
        try JSONSerialization.data(withJSONObject: data).write(to: store.file)
        let restored = TrainingStore(directory: folder)
        XCTAssertTrue(restored.recordActivityInterval(sessionID: id, blockID: block.id,
            activityInstanceID: instance.id, cumulativeElapsedSeconds: 40, exitReason: .paused))
        XCTAssertEqual(restored.data.sessions[0].activityElapsedSeconds(instanceID: instance.id), 0)
        XCTAssertEqual(restored.data.sessions[0].activityIntervals?.first?.baselineOnly, true)
        XCTAssertTrue(restored.recordActivityInterval(sessionID: id, blockID: block.id,
            activityInstanceID: instance.id, cumulativeElapsedSeconds: 45, exitReason: .sessionFinished))
        XCTAssertEqual(restored.data.sessions[0].activityElapsedSeconds(instanceID: instance.id), 5)
    }
    func testCompletionFreezesIntervalsAndOldReceiptsOmitOptionalField() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(directory: folder), block = manualBlock()
        let id = store.start(TrainingTemplate(id: "manual", durationMinutes: 0, blocks: [block]))
        let instance = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id))
        XCTAssertTrue(store.recordActivityInterval(sessionID: id, blockID: block.id,
            activityInstanceID: instance.id, cumulativeElapsedSeconds: 12, exitReason: .sessionFinished))
        store.finish(id, reflection: "")
        var receipt = try XCTUnwrap(TrainingStore(directory: folder).nextPendingWorkoutCompletion())
        XCTAssertFalse(store.recordActivityInterval(sessionID: id, blockID: block.id,
            activityInstanceID: instance.id, cumulativeElapsedSeconds: 20, exitReason: .sessionFinished))
        let interval = try XCTUnwrap((receipt.payload()["activity_intervals"] as? [[String: Any]])?.first)
        XCTAssertEqual(interval["elapsed_seconds"] as? Int, 12)
        XCTAssertEqual(interval["evidence"] as? String, "workout_timer_not_verified_activity")
        receipt.activityIntervals = nil
        let old = try JSONDecoder().decode(WorkoutCompletionReceipt.self, from: JSONEncoder().encode(receipt))
        XCTAssertNil(old.payload()["activity_intervals"])
    }
    func testFailedPersistenceDoesNotAdvanceAttributionCursor() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(directory: folder), block = manualBlock()
        let id = store.start(TrainingTemplate(id: "manual", durationMinutes: 0, blocks: [block]))
        let instance = try XCTUnwrap(store.data.sessions[0].activityInstance(blockID: block.id))
        try FileManager.default.removeItem(at: store.file)
        try FileManager.default.createDirectory(at: store.file, withIntermediateDirectories: false)
        XCTAssertFalse(store.recordActivityInterval(sessionID: id, blockID: block.id,
            activityInstanceID: instance.id, cumulativeElapsedSeconds: 12, exitReason: .paused))
        XCTAssertEqual(store.data.sessions[0].activityIntervals?.count, 0)
        XCTAssertNotNil(store.error)
        try FileManager.default.removeItem(at: store.file)
        XCTAssertTrue(store.recordActivityInterval(sessionID: id, blockID: block.id,
            activityInstanceID: instance.id, cumulativeElapsedSeconds: 15, exitReason: .sessionFinished))
        XCTAssertEqual(store.data.sessions[0].activityElapsedSeconds(instanceID: instance.id), 15)
    }
}
