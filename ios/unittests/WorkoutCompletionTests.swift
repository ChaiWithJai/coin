import XCTest
@testable import Coin

private final class CompletionURLProtocol: URLProtocol {
    static var requests: [[String: Any]] = []
    static var codes: [Int] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        Self.requests.append(payload)
        let code = Self.codes.isEmpty ? 200 : Self.codes.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject:
            ["accepted": true, "event_id": payload["request_id"] ?? "missing"]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class WorkoutCompletionTests: XCTestCase {
    private func template() -> TrainingTemplate {
        let block = SessionBlock(kind: .exercise, minutes: 0, roundNumber: nil, drillID: nil,
            restAfterMinutes: 0, sourceTitle: "Push-ups", sourceBlockID: "p8-strength",
            sourceItemID: "p8-pushups", repetitionText: "3 × 10", completionMode: .manual)
        return TrainingTemplate(id: "source-manual-test", durationMinutes: 0, blocks: [block])
    }
    func testZeroExchangeManualFinishPersistsHonestReceiptAndStableRetryIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory), workout = template()
        let id = store.start(workout, origin: .simulator), block = workout.blocks[0]
        store.recordCueRequest(sessionID: id, blockID: block.id, cueKey: "source_instruction", language: "en", trigger: "stage_start")
        store.recordSegment(sessionID: id, blockID: block.id, activityKey: nil, isRest: false,
            plannedSeconds: 0, elapsedSeconds: 37, exitReason: "manual_completed")
        store.completeBlock(sessionID: id, blockID: block.id, source: "manual_completed")
        store.finish(id, reflection: "")
        let receipt = try XCTUnwrap(store.nextPendingWorkoutCompletion())
        store.finish(id, reflection: "duplicate finish")
        let restored = TrainingStore(directory: directory)
        XCTAssertEqual(restored.nextPendingWorkoutCompletion()?.id, receipt.id)
        XCTAssertEqual(receipt.runtimeOrigin, .simulator)
        XCTAssertEqual(receipt.blocks[0].sourceItemID, "p8-pushups")
        XCTAssertEqual(receipt.blocks[0].completionSources, ["manual_completed"])
        XCTAssertEqual(receipt.blocks[0].segments[0].elapsedSeconds, 37)
        XCTAssertEqual(receipt.blocks[0].cueRequests.first?.cueKey, "source_instruction")
        XCTAssertEqual(receipt.payload()["completion_evidence"] as? String,
            "session_ended_not_verified_adherence")
        restored.recordWorkoutCompletionDelivery(receiptID: receipt.id, eventID: UUID().uuidString)
        XCTAssertNotNil(restored.nextPendingWorkoutCompletion())
        restored.recordWorkoutCompletionDelivery(receiptID: receipt.id, eventID: receipt.id.uuidString.lowercased())
        XCTAssertNil(TrainingStore(directory: directory).nextPendingWorkoutCompletion())
    }
    func testCompletionPayloadOmitsPoseDataAndRemainsStableAcrossPrivacyChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldSetting = UserDefaults.standard.object(forKey: "poseTelemetryEnabled")
        defer { UserDefaults.standard.set(oldSetting, forKey: "poseTelemetryEnabled") }
        let store = TrainingStore(directory: directory)
        var workout = template()
        workout.sourceVersion = "catalog-sha-123"
        let id = store.start(workout, origin: .synthetic)
        store.recordPoseWindows(sessionID: id, windows: [PoseSampleRecord(blockID: workout.blocks[0].id,
            sampledAt: Date(), landmarkCount: 33, sourceVersion: "fixture", framingReady: true)])
        store.finish(id, reflection: "")
        let receipt = try XCTUnwrap(store.nextPendingWorkoutCompletion())
        UserDefaults.standard.set(true, forKey: "poseTelemetryEnabled")
        let first = try JSONSerialization.data(withJSONObject: receipt.payload(), options: [.sortedKeys])
        UserDefaults.standard.set(false, forKey: "poseTelemetryEnabled")
        XCTAssertEqual(first, try JSONSerialization.data(withJSONObject: receipt.payload(), options: [.sortedKeys]))
        XCTAssertEqual(receipt.payload()["source_version"] as? String, "catalog-sha-123")
        let block = try XCTUnwrap((receipt.payload()["blocks"] as? [[String: Any]])?.first)
        XCTAssertNil(block["observed_pose_samples"])
        XCTAssertNil(block["observed_rep_candidates"])
        XCTAssertEqual(receipt.payload()["pose_sharing_enabled"] as? Bool, false)
    }
    func testOldActiveSessionDoesNotAcquirePhysicalOriginOnFinish() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let id = store.start(template(), origin: .physicalDevice)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.file)) as? [String: Any])
        var sessions = try XCTUnwrap(payload["sessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "runtimeOrigin")
        payload["sessions"] = sessions
        try JSONSerialization.data(withJSONObject: payload).write(to: store.file)
        let restored = TrainingStore(directory: directory)
        restored.finish(id, reflection: "")
        XCTAssertEqual(restored.nextPendingWorkoutCompletion()?.runtimeOrigin, .unknown)
    }
    func testTransportFailureRetriesPersistedReceiptWithoutInferenceOrPoseSharing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldSetting = UserDefaults.standard.object(forKey: "poseTelemetryEnabled")
        defer { UserDefaults.standard.set(oldSetting, forKey: "poseTelemetryEnabled") }
        UserDefaults.standard.set(false, forKey: "poseTelemetryEnabled")
        CompletionURLProtocol.requests = []; CompletionURLProtocol.codes = [503, 200]
        let store = TrainingStore(directory: directory), id = store.start(template(), origin: .synthetic)
        store.finish(id, reflection: "")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CompletionURLProtocol.self]
        let sender = WorkoutCompletionSender(session: URLSession(configuration: config),
            endpointOverride: URL(string: "http://127.0.0.1:5290/v1/workout/completion"), tokenOverride: "unit-test")
        sender.sendPending(from: store)
        for _ in 0..<100 where CompletionURLProtocol.requests.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        try await Task.sleep(nanoseconds: 30_000_000)
        let restored = TrainingStore(directory: directory)
        XCTAssertNotNil(restored.nextPendingWorkoutCompletion())
        sender.sendPending(from: restored)
        for _ in 0..<100 where restored.nextPendingWorkoutCompletion() != nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(restored.nextPendingWorkoutCompletion())
        XCTAssertEqual(CompletionURLProtocol.requests.count, 2)
        XCTAssertEqual(CompletionURLProtocol.requests.first?["request_id"] as? String,
            CompletionURLProtocol.requests.last?["request_id"] as? String)
        XCTAssertEqual(CompletionURLProtocol.requests.last?["runtime_origin"] as? String, "synthetic")
        XCTAssertEqual(CompletionURLProtocol.requests.last?["pose_sharing_enabled"] as? Bool, false)
    }
}
