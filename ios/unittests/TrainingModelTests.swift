import XCTest
@testable import Coin

private final class PoseWindowURLProtocol: URLProtocol {
    static var lastPayload: [String: Any]?
    static var lastAuthorization: String?
    static var reached = false
    static var responseCodes: [Int] = []
    static var requestIDs: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.reached = true
        let data: Data?
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var contents = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                contents.append(contentsOf: buffer.prefix(count))
            }
            data = contents
        } else { data = nil }
        guard let data,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestID = payload["request_id"] as? String else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.lastPayload = payload
        Self.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        Self.requestIDs.append(requestID)
        let code = Self.responseCodes.isEmpty ? 200 : Self.responseCodes.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: ["action": "silence", "event_id": requestID]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class TrainingModelTests: XCTestCase {
    func testEngagementEvidencePersistsWithoutPromotingCandidateToTruth() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let template = try XCTUnwrap(SessionTemplates.make(30))
        let sessionID = store.start(template)
        let block = try XCTUnwrap(template.blocks.first { $0.kind == .boxing })
        let span = EngagementPhaseSpan(phase: .initiate, startMs: 200, endMs: 600,
                                       source: .poseCandidate, classifierVersion: "rules-v1")
        let candidate = EngagementAttempt(blockID: block.id, protocolID: "probe-combine-angle-v1",
            startMs: 200, endMs: 1200, spans: [span], cameraCoverage: "partial",
            evidenceSource: .poseCandidate)
        store.recordEngagementAttempt(sessionID: sessionID, attempt: candidate)
        store.recordEngagementAttempt(sessionID: sessionID, attempt: candidate)
        var saved = try XCTUnwrap(TrainingStore(directory: directory).data.sessions.first?.engagementAttempts?.first)
        XCTAssertEqual(TrainingStore(directory: directory).data.sessions.first?.engagementAttempts?.count, 1)
        XCTAssertFalse(saved.isAccepted)
        XCTAssertEqual(saved.spans.first?.phase, .initiate)
        store.correctEngagementAttempt(sessionID: sessionID, attemptID: candidate.id,
                                       note: "I was only stepping in", accept: false)
        saved = try XCTUnwrap(TrainingStore(directory: directory).data.sessions.first?.engagementAttempts?.first)
        XCTAssertFalse(saved.isAccepted)
        XCTAssertEqual(saved.boxerCorrection, "I was only stepping in")
    }
    func testSquatTrackerCountsOnlyFullVisibleCycleAndResetsAfterGap() {
        var tracker = SquatTracker()
        let start = Date()
        func feed(_ angle: Double?, _ offset: Double) -> Bool {
            tracker.observe(angle: angle, at: start.addingTimeInterval(offset))
        }
        for i in 0..<3 { XCTAssertFalse(feed(170, Double(i) * 0.1)) }
        for i in 0..<3 { XCTAssertFalse(feed(90, 0.3 + Double(i) * 0.1)) }
        XCTAssertFalse(feed(170, 0.6))
        XCTAssertFalse(feed(170, 0.7))
        XCTAssertTrue(feed(170, 0.8))
        XCTAssertEqual(tracker.count, 1)
        XCTAssertFalse(feed(nil, 1.8))
        for i in 0..<3 { XCTAssertFalse(feed(170, 1.9 + Double(i) * 0.1)) }
        XCTAssertEqual(tracker.count, 1)
    }
    func testSquatAngleDoesNotRequireVisibleWrists() {
        var joints = Array(repeating: PoseJoint(x: 0.5, y: 0.5, visibility: 0), count: 33)
        for (hip, knee, ankle, x) in [(23, 25, 27, 0.4), (24, 26, 28, 0.6)] {
            joints[hip] = PoseJoint(x: x, y: 0.4, visibility: 0.9)
            joints[knee] = PoseJoint(x: x, y: 0.6, visibility: 0.9)
            joints[ankle] = PoseJoint(x: x, y: 0.8, visibility: 0.9)
        }
        XCTAssertFalse(PoseFraming.fullBodyInFrame(joints))
        XCTAssertEqual(PoseMotion.squatKneeAngle(joints) ?? -1, 180, accuracy: 0.001)
    }

    func testKneeAnglesUsePixelAspectAndAbstainOnInvalidGeometry() {
        var joints = Array(repeating: PoseJoint(x: 0.5, y: 0.5, visibility: 0), count: 33)
        joints[23] = PoseJoint(x: 0.3, y: 0.3, visibility: 0.9)
        joints[25] = PoseJoint(x: 0.5, y: 0.5, visibility: 0.9)
        joints[27] = PoseJoint(x: 0.5, y: 0.8, visibility: 0.9)
        XCTAssertEqual(PoseMotion.squatKneeAngle(joints) ?? -1, 135, accuracy: 0.001)
        XCTAssertEqual(PoseMotion.squatKneeAngle(joints, aspect: 0.5) ?? -1, 153.434949, accuracy: 0.001)
        XCTAssertEqual(PoseMotion.lungeKneeAngle(joints, aspect: 2) ?? -1, 116.565051, accuracy: 0.001)
        for aspect in [0, -1, Double.nan, Double.infinity] {
            XCTAssertNil(PoseMotion.squatKneeAngle(joints, aspect: aspect))
            XCTAssertNil(PoseMotion.lungeKneeAngle(joints, aspect: aspect))
        }
        joints[27] = PoseJoint(x: 0.5, y: 0.8, visibility: 0.1)
        XCTAssertNil(PoseMotion.squatKneeAngle(joints, aspect: 0.5))
    }
    func testTrainingCopyHasFrenchEnglishParityAndMatchingFormatArguments() {
        XCTAssertTrue(Set(TrainingCopy.table.keys).isDisjoint(with: Set(TrainingCopy.base.keys)))
        for (key, variants) in TrainingCopy.table.merging(TrainingCopy.base, uniquingKeysWith: { first, _ in first }) {
            let french = variants["fr"] ?? ""
            let english = variants["en"] ?? ""
            XCTAssertFalse(french.isEmpty, "Missing French: \(key)")
            XCTAssertFalse(english.isEmpty, "Missing English: \(key)")
            for marker in ["%d", "%@"] {
                XCTAssertEqual(french.components(separatedBy: marker).count,
                               english.components(separatedBy: marker).count,
                               "Format mismatch: \(key) \(marker)")
            }
        }
    }
    func testGuardAdviceHasBilingualFallbackForEveryFramingIssue() {
        for issue in ["no_person", "too_close", "joints_hidden", "boxer_too_small", "multiple_people", "unknown"] {
            let french = GuardCopy.advice(issue, true)
            let english = GuardCopy.advice(issue, false)
            XCTAssertFalse(french.hasPrefix("guard_advice_"))
            XCTAssertFalse(english.hasPrefix("guard_advice_"))
            XCTAssertNotEqual(french, english)
        }
        XCTAssertEqual(TrainingCopy.format("guard_coverage", "fr", 42), "Analysable : 42 % du round")
        XCTAssertEqual(TrainingCopy.format("guard_coverage", "en", 42), "Analysable: 42% of the round")
    }
    func testEveryTemplateMatchesItsDurationAndHasRoundStructure() {
        XCTAssertEqual(SessionTemplates.all.map(\.durationMinutes), [30, 50, 60, 75, 90])
        for template in SessionTemplates.all {
            XCTAssertEqual(template.plannedMinutes, template.durationMinutes)
            XCTAssertEqual(template.blocks.first?.kind, .warmup)
            XCTAssertEqual(template.blocks.first?.activities?.reduce(0) { $0 + $1.minutes }, template.blocks.first?.minutes)
            XCTAssertEqual(template.blocks.first?.activities?.map(\.key), ["mobility", "squats", "lunges", "shadowboxing"])
            XCTAssertEqual(template.blocks.last?.kind, .cooldown)
            XCTAssertEqual(template.blocks.filter { $0.kind == .boxing }.count, template.boxingRounds)
            XCTAssertTrue(template.blocks.filter { $0.kind == .boxing }.allSatisfy { $0.minutes == 3 && $0.restAfterMinutes == 1 && $0.drillID != nil })
            XCTAssertTrue(template.blocks.filter { $0.kind == .boxing }.allSatisfy { $0.drillID == "probe-combine-angle-v1" })
        }
    }

    func testPoseOverlayMatchesAspectFillAndMirror() {
        let preview = CGSize(width: 390, height: 844)
        let video = CGSize(width: 1080, height: 1920)
        let center = PoseOverlayMapping.point(CGPoint(x: 0.5, y: 0.5), preview: preview, video: video, mirrored: false)
        XCTAssertEqual(center.x, 195, accuracy: 0.01)
        XCTAssertEqual(center.y, 422, accuracy: 0.01)
        let left = PoseOverlayMapping.point(CGPoint(x: 0.2, y: 0.5), preview: preview, video: video, mirrored: false)
        let reflected = PoseOverlayMapping.point(CGPoint(x: 0.2, y: 0.5), preview: preview, video: video, mirrored: true)
        XCTAssertEqual(left.x + reflected.x, 390, accuracy: 0.01)
        XCTAssertLessThan(left.x, 195)
        var joints = Array(repeating: PoseJoint(x: 0.5, y: 0.5, visibility: 0), count: 33)
        joints[11] = PoseJoint(x: 0.3, y: 0.4, visibility: 1)
        joints[12] = PoseJoint(x: 0.7, y: 0.4, visibility: 1)
        joints[13] = PoseJoint(x: 0.2, y: 0.6, visibility: 0.1)
        let visible = PoseOverlayMapping.visiblePoints(joints)
        XCTAssertEqual(Set(visible.keys), [11, 12])
        XCTAssertTrue(PoseOverlayMapping.bodyConnections.contains { $0 == 11 && $1 == 12 })
        XCTAssertNil(visible[13])
    }

    func testWristMotionRequiresVisibleJointsAndDiscountsCameraShift() {
        var first = Array(repeating: PoseJoint(x: 0.5, y: 0.5, visibility: 1), count: 33)
        first[11] = PoseJoint(x: 0.35, y: 0.35, visibility: 1)
        first[12] = PoseJoint(x: 0.65, y: 0.35, visibility: 1)
        first[15] = PoseJoint(x: 0.34, y: 0.48, visibility: 1)
        first[16] = PoseJoint(x: 0.66, y: 0.48, visibility: 1)
        first[23] = PoseJoint(x: 0.42, y: 0.65, visibility: 1)
        first[24] = PoseJoint(x: 0.58, y: 0.65, visibility: 1)
        let shifted = first.map { PoseJoint(x: $0.x + 0.05, y: $0.y, visibility: $0.visibility) }
        XCTAssertEqual(PoseMotion.wristTravelBodyWidths(previous: first, current: shifted) ?? -1, 0, accuracy: 0.001)
        var moving = first
        moving[15] = PoseJoint(x: 0.49, y: 0.48, visibility: 1)
        XCTAssertGreaterThan(PoseMotion.wristTravelBodyWidths(previous: first, current: moving) ?? 0, 0.4)
        moving[15] = PoseJoint(x: 0.49, y: 0.48, visibility: 0.1)
        XCTAssertNil(PoseMotion.wristTravelBodyWidths(previous: first, current: moving))
    }

    func testWristMotionUsesOnePixelMetricForTravelAndShoulderScale() {
        var first = Array(repeating: PoseJoint(x: 0.5, y: 0.5, visibility: 1), count: 33)
        first[11] = PoseJoint(x: 0.35, y: 0.35, visibility: 1)
        first[12] = PoseJoint(x: 0.65, y: 0.35, visibility: 1)
        first[15] = PoseJoint(x: 0.35, y: 0.45, visibility: 1)
        var current = first
        current[15] = PoseJoint(x: 0.35, y: 0.6, visibility: 1)
        XCTAssertEqual(PoseMotion.wristTravelBodyWidths(previous: first, current: current) ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(PoseMotion.wristTravelBodyWidths(previous: first, current: current, aspect: 0.5) ?? -1, 1, accuracy: 0.001)
        // Represent the same pixels on a square canvas: corrected travel must agree.
        let squareFirst = first.map { PoseJoint(x: $0.x * 0.5, y: $0.y, visibility: $0.visibility) }
        let squareCurrent = current.map { PoseJoint(x: $0.x * 0.5, y: $0.y, visibility: $0.visibility) }
        XCTAssertEqual(PoseMotion.wristTravelBodyWidths(previous: squareFirst, current: squareCurrent),
                       PoseMotion.wristTravelBodyWidths(previous: first, current: current, aspect: 0.5))
        let translated = first.map { PoseJoint(x: $0.x + 0.05, y: $0.y + 0.02, visibility: $0.visibility) }
        XCTAssertEqual(PoseMotion.wristTravelBodyWidths(previous: first, current: translated, aspect: 0.5) ?? -1, 0, accuracy: 0.001)
        XCTAssertNil(PoseMotion.wristTravelBodyWidths(previous: first, current: current, aspect: .nan))
        XCTAssertNil(PoseMotion.wristTravelBodyWidths(previous: first, current: current, aspect: 0))
    }

    func testRoundPromptsMatchAssignedDrillInBothLanguages() {
        for drill in DrillLibrary.all {
            let key = DrillLibrary.speechKey(drill.id)
            for language in ["fr", "en"] {
                let prompt = TrainingCopy.text(key, language)
                XCTAssertFalse(prompt.contains("%d"))
                XCTAssertFalse(prompt.isEmpty)
                XCTAssertFalse(prompt.contains(key))
                for boundary in [120, 60] {
                    let cueKey = DrillLibrary.pacingCueKey(drill.id, remainingSeconds: boundary)
                    XCTAssertNotNil(cueKey)
                    XCTAssertNotEqual(TrainingCopy.text(cueKey ?? "", language), cueKey)
                }
            }
        }
        XCTAssertEqual(DrillLibrary.phaseKeys("probe-combine-angle-v1"), ["phase_jab", "phase_combine", "phase_angle"])
        XCTAssertEqual(DrillLibrary.phaseKeys("guard-return-v1"), ["phase_jab", "phase_guard"])
        XCTAssertTrue(DrillLibrary.phaseKeys("free-boxing-v1").isEmpty)
        XCTAssertNil(DrillLibrary.pacingCueKey("free-boxing-v1", remainingSeconds: 90))
        XCTAssertEqual(DrillLibrary.focusCueKey("probe-combine-angle-v1", remainingSeconds: 180), "round_speech")
        XCTAssertEqual(DrillLibrary.focusCueKey("probe-combine-angle-v1", remainingSeconds: 120), "probe_mid_cue")
        XCTAssertEqual(DrillLibrary.focusCueKey("probe-combine-angle-v1", remainingSeconds: 60), "probe_late_cue")
    }

    func testSessionLogPersistsPlanChangesEvidenceAndCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let template = try XCTUnwrap(SessionTemplates.make(30))
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let id = store.start(template, at: started)
        let rounds = try XCTUnwrap(store.data.sessions.first?.blocks.filter { $0.kind == .boxing })
        let first = try XCTUnwrap(rounds.first)
        let second = rounds[1]
        store.completeBlock(sessionID: id, blockID: first.id)
        store.completeBlock(sessionID: id, blockID: first.id)
        store.recordTimedSeconds(sessionID: id, seconds: 180)
        store.setDrill(sessionID: id, blockID: second.id, drillID: "footwork-angle-v1")
        store.finish(id, reflection: "Only one round completed", at: started.addingTimeInterval(600))
        store.updateReflection(id, text: "  Jab, then angle.  ")

        let restored = TrainingStore(directory: directory)
        let session = try XCTUnwrap(restored.data.sessions.first)
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.completedRoundCount, 1)
        XCTAssertEqual(session.timedRoundCount, 0)
        XCTAssertEqual(session.blockLogs?.count, 1)
        XCTAssertEqual(session.blockLogs?.first?.evidenceSource, "boxer_check_in")
        XCTAssertEqual(session.blocks.first(where: { $0.id == second.id })?.drillID, "footwork-angle-v1")
        XCTAssertEqual(session.reflection, "Jab, then angle.")
        XCTAssertEqual(restored.sessions(on: started).count, 1)
        XCTAssertEqual(session.loggedMinutes, 3)
        XCTAssertEqual(session.elapsedClock, "03:00")
    }

    func testPartialTimedWorkSurvivesEarlyFinish() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let id = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        store.recordTimedSeconds(sessionID: id, seconds: 75)
        store.finish(id, reflection: "")
        let restored = try XCTUnwrap(TrainingStore(directory: directory).data.sessions.first)
        XCTAssertEqual(restored.completedRoundCount, 0)
        XCTAssertEqual(restored.elapsedClock, "01:15")
        XCTAssertEqual(restored.loggedMinutes, 1)
    }

    func testRoundEvidenceSeparatesReachedTimedAndManualCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let id = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        let rounds = try XCTUnwrap(store.data.sessions.first?.blocks.filter { $0.kind == .boxing })
        store.recordSegment(sessionID: id, blockID: rounds[0].id, activityKey: nil,
                            isRest: false, plannedSeconds: 180, elapsedSeconds: 13, exitReason: "skipped")
        store.recordSegment(sessionID: id, blockID: rounds[1].id, activityKey: nil,
                            isRest: false, plannedSeconds: 180, elapsedSeconds: 180, exitReason: "timer_elapsed")
        store.completeBlock(sessionID: id, blockID: rounds[2].id, source: "boxer_check_in")
        store.finish(id, reflection: "")
        let session = try XCTUnwrap(TrainingStore(directory: directory).data.sessions.first)
        XCTAssertEqual(session.reachedRoundCount, 2)
        XCTAssertEqual(session.timedRoundCount, 1)
        XCTAssertEqual(session.completedRoundCount, 1)
    }

    func testRoundDrillCannotBeRewrittenAfterTimedEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let id = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        let round = try XCTUnwrap(store.data.sessions.first?.blocks.first { $0.kind == .boxing })
        store.setDrill(sessionID: id, blockID: round.id, drillID: "guard-return-v1")
        XCTAssertEqual(store.data.sessions.first?.blocks.first { $0.id == round.id }?.drillID, "guard-return-v1")
        store.recordSegment(sessionID: id, blockID: round.id, activityKey: nil,
                            isRest: false, plannedSeconds: 180, elapsedSeconds: 13, exitReason: "skipped")
        store.setDrill(sessionID: id, blockID: round.id, drillID: "footwork-angle-v1")
        XCTAssertEqual(TrainingStore(directory: directory).data.sessions.first?.blocks.first { $0.id == round.id }?.drillID,
                       "guard-return-v1")
    }

    func testHomeResumeKeepsActiveSessionAndItsEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let firstTemplate = try XCTUnwrap(SessionTemplates.make(30))
        let secondTemplate = try XCTUnwrap(SessionTemplates.make(60))
        let id = store.resumeOrStart(firstTemplate)
        store.recordTimedSeconds(sessionID: id, seconds: 13)
        XCTAssertEqual(store.resumeOrStart(secondTemplate), id)
        XCTAssertEqual(store.data.sessions.count, 1)
        XCTAssertEqual(store.data.sessions.first?.plannedMinutes, 30)
        XCTAssertEqual(store.data.sessions.first?.elapsedClock, "00:13")
        store.finish(id, reflection: "")
        XCTAssertNotEqual(store.resumeOrStart(secondTemplate), id)
        XCTAssertEqual(store.data.sessions.count, 2)
    }

    func testSegmentLogDistinguishesSkippedAndTimedWork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let id = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        let warmup = try XCTUnwrap(store.data.sessions.first?.blocks.first)
        store.recordSegment(sessionID: id, blockID: warmup.id, activityKey: "mobility", isRest: false,
                            plannedSeconds: 120, elapsedSeconds: 35, exitReason: "skipped")
        store.recordSegment(sessionID: id, blockID: warmup.id, activityKey: "squats", isRest: false,
                            plannedSeconds: 120, elapsedSeconds: 120, exitReason: "timer_elapsed")
        store.recordSegment(sessionID: id, blockID: warmup.id, activityKey: "lunges", isRest: false,
                            plannedSeconds: 120, elapsedSeconds: 121, exitReason: "timer_elapsed")
        let saved = try XCTUnwrap(TrainingStore(directory: directory).data.sessions.first)
        XCTAssertEqual(saved.segmentLogs?.count, 2)
        XCTAssertEqual(saved.segmentLogs?.first?.elapsedSeconds, 35)
        XCTAssertEqual(saved.segmentLogs?.first?.exitReason, "skipped")
        XCTAssertEqual(saved.segmentLogs?.last?.activityKey, "squats")
    }

    func testSegmentTraversalIndicesPersistAndOlderLogsStillDecode() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let id = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        let block = try XCTUnwrap(store.data.sessions.first?.blocks.first)
        store.recordSegment(sessionID: id, blockID: block.id, activityKey: "mobility", isRest: false,
                            plannedSeconds: 120, elapsedSeconds: 120, exitReason: "timer_elapsed",
                            segmentIndex: 4, preparationIndex: 2)
        let saved = try XCTUnwrap(TrainingStore(directory: directory).data.sessions.first?.segmentLogs?.first)
        XCTAssertEqual(saved.segmentIndex, 4)
        XCTAssertEqual(saved.preparationIndex, 2)

        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","blockID":"00000000-0000-0000-0000-000000000002","isRest":false,"plannedSeconds":120,"elapsedSeconds":120,"exitReason":"timer_elapsed","endedAt":0}
        """
        let decoded = try JSONDecoder().decode(SegmentLog.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.segmentIndex)
        XCTAssertNil(decoded.preparationIndex)
    }

    func testCampDatesAndWeightMeasurementsPersist() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.addMilestone(kind: .fightDate, date: date, title: "Fight", weightClass: "Welterweight")
        store.addWeight(70.4, unit: "kg", at: date)
        store.addWeight(-4, unit: "kg", at: date)
        let restored = TrainingStore(directory: directory)
        XCTAssertEqual(restored.data.milestones.first?.kind, .fightDate)
        XCTAssertEqual(restored.data.milestones.first?.weightClass, "Welterweight")
        XCTAssertEqual(restored.data.weightRecords?.count, 1)
        XCTAssertEqual(restored.data.weightRecords?.first?.amount, 70.4)
    }

    func testTimerLogSeparatesRoundFromRestAndPersistsPosition() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let id = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        let round = try XCTUnwrap(store.data.sessions.first?.blocks.first(where: { $0.kind == .boxing }))
        store.completeBlock(sessionID: id, blockID: round.id, source: "timer_elapsed")
        store.recordTimedSeconds(sessionID: id, seconds: 180)
        store.saveRuntime(sessionID: id, segmentIndex: 2, remainingSeconds: 41)
        var saved = try XCTUnwrap(TrainingStore(directory: directory).data.sessions.first)
        XCTAssertEqual(saved.loggedMinutes, 3)
        XCTAssertEqual(saved.runtimeSegmentIndex, 2)
        XCTAssertEqual(saved.runtimeRemainingSeconds, 41)
        store.recordRestElapsed(sessionID: id, blockID: round.id)
        store.recordRestElapsed(sessionID: id, blockID: round.id)
        store.recordTimedSeconds(sessionID: id, seconds: 60)
        saved = try XCTUnwrap(TrainingStore(directory: directory).data.sessions.first)
        XCTAssertEqual(saved.loggedMinutes, 4)
        XCTAssertEqual(saved.blockLogs?.count, 2)
    }

    func testPoseEvidenceIsSampledVisibilityNotDrillCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let sessionID = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        let round = try XCTUnwrap(store.data.sessions.first?.blocks.first(where: { $0.kind == .boxing }))
        let now = Date()
        store.recordPoseWindows(sessionID: sessionID, windows: [
            PoseSampleRecord(blockID: round.id, sampledAt: now, landmarkCount: 33, sourceVersion: "mediapipe-pose-full-v1", visibleLandmarkCount: 33, framingReady: true),
            PoseSampleRecord(blockID: round.id, sampledAt: now.addingTimeInterval(2), landmarkCount: 33, sourceVersion: "mediapipe-pose-full-v1", visibleLandmarkCount: 12, framingReady: false),
        ])
        let restored = try XCTUnwrap(TrainingStore(directory: directory).data.sessions.first)
        XCTAssertEqual(restored.poseEvidence(for: round.id).visible, 1)
        XCTAssertEqual(restored.poseEvidence(for: round.id).sampled, 2)
        XCTAssertEqual(restored.completedRoundCount, 0)
        XCTAssertEqual(restored.loggedMinutes, 0)
    }

    func testPoseLatencyPersistsAndRejectsInvalidSamples() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let sessionID = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        let blockID = try XCTUnwrap(store.data.sessions.first?.blocks.first?.id)
        let samples = (1...20).map { index in
            PoseSampleRecord(blockID: blockID, sampledAt: Date(), landmarkCount: 33,
                             sourceVersion: "mediapipe-pose-full-v1", visibleLandmarkCount: 12,
                             framingReady: false, captureToPoseMs: Double(index * 10),
                             wristTravelBodyWidths: 0.42)
        }
        store.recordPoseWindows(sessionID: sessionID, windows: samples + [
            PoseSampleRecord(blockID: blockID, sampledAt: Date(), landmarkCount: 33,
                             sourceVersion: "mediapipe-pose-full-v1", visibleLandmarkCount: 34,
                             framingReady: false, captureToPoseMs: 1),
            PoseSampleRecord(blockID: blockID, sampledAt: Date(), landmarkCount: 33,
                             sourceVersion: "mediapipe-pose-full-v1", visibleLandmarkCount: 12,
                             framingReady: false, captureToPoseMs: .infinity),
            PoseSampleRecord(blockID: blockID, sampledAt: Date(), landmarkCount: 33,
                             sourceVersion: "mediapipe-pose-full-v1", visibleLandmarkCount: 12,
                             framingReady: false, captureToPoseMs: 1,
                             wristTravelBodyWidths: .infinity),
        ])
        let restored = try XCTUnwrap(TrainingStore(directory: directory).data.sessions.first)
        XCTAssertEqual(restored.poseWindows?.count, 20)
        XCTAssertEqual(restored.poseLatencyP95Ms, 190)
        XCTAssertEqual(restored.poseWindows?.first?.wristTravelBodyWidths, 0.42)
    }

    func testPoseDeliveryIsLinkedOnlyToAnExistingSample() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let sessionID = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        let blockID = try XCTUnwrap(store.data.sessions.first?.blocks.first?.id)
        let sample = PoseSampleRecord(blockID: blockID, sampledAt: Date(), landmarkCount: 33,
                                      sourceVersion: "mediapipe-pose-full-v1")
        var selected = sample
        selected.activityInstanceID = UUID()
        store.recordPoseWindows(sessionID: sessionID, windows: [selected])
        XCTAssertTrue((store.data.sessions.first?.poseWindows ?? []).isEmpty)
        selected.activityInstanceID = store.data.sessions.first?.activityInstances?.first { $0.blockID == blockID }?.id
        selected.uploadLanguage = "fr"
        store.recordPoseWindows(sessionID: sessionID, windows: [selected])
        XCTAssertEqual(TrainingStore(directory: directory).nextPendingPoseUpload()?.sample.id, sample.id)
        XCTAssertEqual(store.data.sessions.first?.poseUploadEvidence.selected, 1)
        XCTAssertEqual(store.data.sessions.first?.poseUploadEvidence.acknowledged, 0)
        store.recordPoseDelivery(sessionID: sessionID, sampleID: UUID(), eventID: UUID().uuidString)
        XCTAssertNil(store.data.sessions.first?.poseWindows?.first?.remoteEventID)
        store.recordPoseDelivery(sessionID: sessionID, sampleID: sample.id, eventID: UUID().uuidString)
        XCTAssertNil(store.data.sessions.first?.poseWindows?.first?.remoteEventID)
        let eventID = sample.id.uuidString
        store.recordPoseDelivery(sessionID: sessionID, sampleID: sample.id, eventID: eventID)
        let restored = TrainingStore(directory: directory)
        XCTAssertEqual(restored.data.sessions.first?.poseWindows?.first?.remoteEventID, eventID)
        XCTAssertEqual(restored.data.sessions.first?.poseUploadEvidence.acknowledged, 1)
        XCTAssertNil(restored.nextPendingPoseUpload())
    }

    func testPoseSenderPostsBoundedAggregateAndPersistsReceipt() async throws {
        PoseWindowURLProtocol.reached = false
        PoseWindowURLProtocol.lastPayload = nil
        PoseWindowURLProtocol.responseCodes = []
        PoseWindowURLProtocol.requestIDs = []
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let priorConsent = UserDefaults.standard.bool(forKey: "poseTelemetryEnabled")
        UserDefaults.standard.set(true, forKey: "poseTelemetryEnabled")
        defer { UserDefaults.standard.set(priorConsent, forKey: "poseTelemetryEnabled") }
        let store = TrainingStore(directory: directory)
        let sessionID = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        let blockID = try XCTUnwrap(store.data.sessions.first?.blocks.first?.id)
        let activityID = try XCTUnwrap(store.data.sessions.first?.activityInstances?.first { $0.blockID == blockID }?.id)
        var sample = PoseSampleRecord(blockID: blockID, sampledAt: Date(), landmarkCount: 33,
                                      sourceVersion: "mediapipe-pose-full-v1", visibleLandmarkCount: 12,
                                      framingReady: false, captureToPoseMs: 38.5,
                                      wristTravelBodyWidths: 0.42, lowerBodyVisible: true)
        sample.activityInstanceID = activityID
        sample.activityKey = "mobility"
        sample.measurementID = "session-clock"
        sample.measurementVersion = "v1"
        sample.measurementCapability = "elapsed_only"
        sample.uploadLanguage = "fr"
        store.recordPoseWindows(sessionID: sessionID, windows: [sample])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PoseWindowURLProtocol.self]
        let sender = PoseWindowSender(session: URLSession(configuration: configuration),
                                      endpointOverride: URL(string: "https://example.invalid/v1/live/pose-window")!,
                                      tokenOverride: "fixture-token")
        sender.sendPending(from: store)
        for _ in 0..<50 where store.data.sessions.first?.poseWindows?.first?.remoteEventID == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(PoseWindowURLProtocol.reached, "URLProtocol was never invoked")
        XCTAssertFalse(sender.offline, "Sender rejected the mock response")
        XCTAssertEqual(store.data.sessions.first?.poseWindows?.first?.remoteEventID, sample.id.uuidString)
        XCTAssertEqual(PoseWindowURLProtocol.lastPayload?["session_id"] as? String, sessionID.uuidString)
        XCTAssertEqual(PoseWindowURLProtocol.lastPayload?["activity_instance_id"] as? String, activityID.uuidString)
        XCTAssertEqual(PoseWindowURLProtocol.lastPayload?["activity_key"] as? String, "mobility")
        XCTAssertEqual(PoseWindowURLProtocol.lastPayload?["measurement_id"] as? String, "session-clock")
        XCTAssertEqual(PoseWindowURLProtocol.lastPayload?["measurement_version"] as? String, "v1")
        XCTAssertEqual(PoseWindowURLProtocol.lastPayload?["measurement_capability"] as? String, "elapsed_only")
        XCTAssertEqual(PoseWindowURLProtocol.lastPayload?["runtime_origin"] as? String, "simulator")
        XCTAssertEqual(PoseWindowURLProtocol.lastPayload?["visible_landmark_count"] as? Int, 12)
        XCTAssertEqual(PoseWindowURLProtocol.lastPayload?["language"] as? String, "fr")
        XCTAssertEqual(PoseWindowURLProtocol.lastPayload?["wrist_travel_body_widths"] as? Double, 0.42)
        XCTAssertEqual(PoseWindowURLProtocol.lastPayload?["lower_body_visible"] as? Bool, true)
        XCTAssertNil(PoseWindowURLProtocol.lastPayload?["image"])
        XCTAssertEqual(PoseWindowURLProtocol.lastAuthorization, "Bearer fixture-token")
    }

    func testPoseSenderRetriesSameRequestAfterServerFailure() async throws {
        PoseWindowURLProtocol.responseCodes = [503, 200]
        PoseWindowURLProtocol.requestIDs = []
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let priorConsent = UserDefaults.standard.bool(forKey: "poseTelemetryEnabled")
        UserDefaults.standard.set(true, forKey: "poseTelemetryEnabled")
        defer { UserDefaults.standard.set(priorConsent, forKey: "poseTelemetryEnabled") }
        let store = TrainingStore(directory: directory)
        let sessionID = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        let blockID = try XCTUnwrap(store.data.sessions.first?.blocks.first?.id)
        var sample = PoseSampleRecord(blockID: blockID, sampledAt: Date(), landmarkCount: 33,
                                      sourceVersion: "mediapipe-pose-full-v1", visibleLandmarkCount: 12,
                                      framingReady: false)
        sample.uploadLanguage = "en"
        store.recordPoseWindows(sessionID: sessionID, windows: [sample])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PoseWindowURLProtocol.self]
        let sender = PoseWindowSender(session: URLSession(configuration: configuration),
                                      endpointOverride: URL(string: "https://example.invalid/v1/live/pose-window")!,
                                      tokenOverride: "fixture-token")
        sender.sendPending(from: store)
        for _ in 0..<50 where !sender.offline { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertTrue(sender.offline)
        XCTAssertNotNil(store.nextPendingPoseUpload())
        try await Task.sleep(nanoseconds: 100_000_000)
        sender.sendPending(from: store)
        for _ in 0..<50 where store.nextPendingPoseUpload() != nil { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(PoseWindowURLProtocol.requestIDs, [sample.id.uuidString, sample.id.uuidString])
        XCTAssertEqual(store.data.sessions.first?.poseWindows?.first?.remoteEventID, sample.id.uuidString)
    }

    func testCueRequestsPersistWithoutClaimingAudioPlayback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let sessionID = store.start(try XCTUnwrap(SessionTemplates.make(30)))
        let blockID = try XCTUnwrap(store.data.sessions.first?.blocks.first?.id)
        store.recordCueRequest(sessionID: sessionID, blockID: blockID, cueKey: "mobility_cue",
                               language: "fr", trigger: "stage_start")
        store.recordCueRequest(sessionID: sessionID, blockID: blockID, cueKey: "made_up",
                               language: "fr", trigger: "stage_start")
        let restored = try XCTUnwrap(TrainingStore(directory: directory).data.sessions.first)
        XCTAssertEqual(restored.cueRequests?.count, 1)
        XCTAssertEqual(restored.cueRequests?.first?.cueKey, "mobility_cue")
        XCTAssertEqual(restored.cueRequests?.first?.trigger, "stage_start")
    }

    func testFullBodyFramingRejectsCroppedPoseDespiteAllLandmarkSlots() {
        var joints = (0..<33).map { _ in PoseJoint(x: 0.5, y: 0.5, visibility: 0.9) }
        XCTAssertTrue(PoseFraming.fullBodyInFrame(joints))
        joints[27] = PoseJoint(x: 0.5, y: 1.2, visibility: 0.9)
        XCTAssertFalse(PoseFraming.fullBodyInFrame(joints))
        joints[27] = PoseJoint(x: 0.5, y: 0.9, visibility: 0.2)
        XCTAssertFalse(PoseFraming.fullBodyInFrame(joints))
    }

    func testStartingAgainPreservesInterruptedSessionAndItsEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrainingStore(directory: directory)
        let first = store.start(try XCTUnwrap(SessionTemplates.make(30)), at: Date(timeIntervalSince1970: 1000))
        let round = try XCTUnwrap(store.data.sessions.first?.blocks.first(where: { $0.kind == .boxing }))
        store.completeBlock(sessionID: first, blockID: round.id, source: "timer_elapsed")
        store.recordTimedSeconds(sessionID: first, seconds: 180)
        let second = store.start(try XCTUnwrap(SessionTemplates.make(50)), at: Date(timeIntervalSince1970: 1600))
        let restored = TrainingStore(directory: directory).data.sessions
        XCTAssertEqual(restored.first?.id, second)
        XCTAssertEqual(restored.first?.state, .active)
        let previous = try XCTUnwrap(restored.first(where: { $0.id == first }))
        XCTAssertEqual(previous.state, .interrupted)
        XCTAssertEqual(previous.endReason, "new_session_started")
        XCTAssertEqual(previous.endedAt, Date(timeIntervalSince1970: 1600))
        XCTAssertEqual(previous.completedRoundCount, 1)
        XCTAssertEqual(previous.loggedMinutes, 3)
    }
}
