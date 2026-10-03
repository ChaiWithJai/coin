import XCTest
import CryptoKit
@testable import Coin

@MainActor final class RuntimeDrillProposalTests: XCTestCase {
    private let catalogHash = String(repeating: "c", count: 64)
    private let reviewed = RuntimeDrillProposal.Review(
        state: .approved, reviewer: "reviewer@example.test", reviewedAt: Date(timeIntervalSince1970: 1_800_000_000))

    private var lesson: WorkoutLesson {
        get throws { try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d6" }) }
    }

    private func itemProposal() throws -> RuntimeDrillProposal {
        let lesson = try lesson
        let source = try XCTUnwrap(lesson.blocks.first)
        let item = try XCTUnwrap(source.sourceItems?.first { $0.id == "p8-b6" })
        return .init(schemaVersion: 1, proposalID: "basic-w1-d6-squat-v1",
            catalogSHA256: catalogHash, sourceSHA256: lesson.sourceSHA256,
            target: .init(kind: .sourceItem, lessonID: lesson.id, sourceBlockID: source.id,
                          sourceItemID: item.id, runtimeSegmentIndex: nil),
            sourceTitle: source.title, sourceInstructions: source.instructions, sourceItemText: item.text,
            runtimeTitle: nil, runtimeInstructions: nil,
            movementKey: "squats", movementVersion: "v1",
            measurementRecipe: .forExercise("squats"), review: reviewed, measurementReview: reviewed)
    }

    func testApprovedAtomicItemCompilesWithoutChangingSourceWording() throws {
        let proposal = try itemProposal()
        let encoded = try JSONEncoder().encode(proposal)
        let decoded = try JSONDecoder().decode(RuntimeDrillProposal.self, from: encoded)
        XCTAssertEqual(decoded, proposal)

        let result = RuntimeDrillCompiler.promote(decoded, catalog: WorkoutCatalog.shared,
                                                   catalogSHA256: catalogHash)
        guard case .promoted(let drill) = result else { return XCTFail("Expected promotion, got \(result)") }
        XCTAssertEqual(drill.sourceItemID, "p8-b6")
        XCTAssertEqual(drill.movementKey, "squats")
        XCTAssertEqual(drill.measurementRecipe.capability, .repCandidate)
        let sourceLesson = try lesson
        let original = try XCTUnwrap(sourceLesson.blocks.first?.sourceItems?.first { $0.id == "p8-b6" }?.text)
        XCTAssertEqual(original, "Squat")
    }

    func testUnreviewedProposalAndRecipeAlwaysAbstain() throws {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try itemProposal())) as? [String: Any])
        var review = try XCTUnwrap(raw["review"] as? [String: Any])
        review["state"] = "unreviewed"
        raw["review"] = review
        var proposal = try JSONDecoder().decode(RuntimeDrillProposal.self,
            from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(RuntimeDrillCompiler.promote(proposal, catalog: WorkoutCatalog.shared,
            catalogSHA256: catalogHash), .abstained(.proposalNotApproved))

        raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try itemProposal())) as? [String: Any])
        var measurement = try XCTUnwrap(raw["measurementReview"] as? [String: Any])
        measurement["state"] = "unreviewed"
        raw["measurementReview"] = measurement
        proposal = try JSONDecoder().decode(RuntimeDrillProposal.self,
            from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(RuntimeDrillCompiler.promote(proposal, catalog: WorkoutCatalog.shared,
            catalogSHA256: catalogHash), .abstained(.measurementNotApproved))
    }

    func testHashesWordingAndRecipeAreFailClosed() throws {
        let original = try itemProposal()
        func changed(_ edit: (inout [String: Any]) -> Void) throws -> RuntimeDrillProposal {
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            edit(&raw)
            return try JSONDecoder().decode(RuntimeDrillProposal.self,
                from: JSONSerialization.data(withJSONObject: raw))
        }
        let cases: [(RuntimeDrillProposal, RuntimeDrillAbstention)] = [
            (try changed { $0["catalogSHA256"] = String(repeating: "d", count: 64) }, .invalidCatalogHash),
            (try changed { $0["sourceSHA256"] = String(repeating: "d", count: 64) }, .sourceHashMismatch),
            (try changed { $0["sourceItemText"] = "Squat and press" }, .sourceWordingMismatch),
            (try changed { raw in var recipe = raw["measurementRecipe"] as! [String: Any];
                recipe["id"] = "session-clock"; raw["measurementRecipe"] = recipe }, .measurementRecipeMismatch),
        ]
        for (proposal, reason) in cases {
            XCTAssertEqual(RuntimeDrillCompiler.promote(proposal, catalog: WorkoutCatalog.shared,
                catalogSHA256: catalogHash), .abstained(reason))
        }
    }

    func testExpandedRuntimeSegmentRequiresExactIndexLineageAndWording() throws {
        let lesson = try XCTUnwrap(WorkoutCatalog.shared.lessons.first { $0.id == "basic-w1-d1" })
        let blocks = lesson.template().blocks
        let index = try XCTUnwrap(blocks.firstIndex { $0.sourceBlockID == "basic-w1-d1-p3-s3-1" })
        let segment = blocks[index]
        let proposal = RuntimeDrillProposal(schemaVersion: 1, proposalID: "frontal-segment-0-v1",
            catalogSHA256: catalogHash, sourceSHA256: lesson.sourceSHA256,
            target: .init(kind: .runtimeSegment, lessonID: lesson.id,
                sourceBlockID: try XCTUnwrap(segment.sourceBlockID), sourceItemID: segment.sourceItemID,
                runtimeSegmentIndex: index),
            sourceTitle: try XCTUnwrap(lesson.blocks.first { $0.id == segment.sourceBlockID }?.title),
            sourceInstructions: try XCTUnwrap(lesson.blocks.first { $0.id == segment.sourceBlockID }?.instructions),
            sourceItemText: nil, runtimeTitle: segment.sourceTitle,
            runtimeInstructions: segment.sourceInstructions,
            movementKey: "frontal_stance", movementVersion: "v1",
            measurementRecipe: .forExercise("frontal_stance"), review: reviewed, measurementReview: reviewed)
        guard case .promoted(let compiled) = RuntimeDrillCompiler.promote(proposal,
            catalog: WorkoutCatalog.shared, catalogSHA256: catalogHash) else {
            return XCTFail("Exact runtime segment should compile")
        }
        XCTAssertEqual(compiled.runtimeSegmentIndex, index)
        XCTAssertEqual(compiled.measurementRecipe.capability, .elapsedOnly)

        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        var target = try XCTUnwrap(raw["target"] as? [String: Any])
        target["runtimeSegmentIndex"] = index + 4
        raw["target"] = target
        let moved = try JSONDecoder().decode(RuntimeDrillProposal.self,
            from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(RuntimeDrillCompiler.promote(moved, catalog: WorkoutCatalog.shared,
            catalogSHA256: catalogHash), .abstained(.runtimeLineageMismatch))
    }

    func testWholeBlockCannotMasqueradeAsAtomicSourceItem() throws {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try itemProposal())) as? [String: Any])
        var target = try XCTUnwrap(raw["target"] as? [String: Any])
        target.removeValue(forKey: "sourceItemID")
        raw["target"] = target
        raw.removeValue(forKey: "sourceItemText")
        let proposal = try JSONDecoder().decode(RuntimeDrillProposal.self,
            from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(RuntimeDrillCompiler.promote(proposal, catalog: WorkoutCatalog.shared,
            catalogSHA256: catalogHash), .abstained(.targetNotAtomic))
    }

    func testCompleteReviewedOverlayChangesOnlyMovementMetadata() throws {
        let fixture = try overlayFixture(blockCount: 1)
        let overlay = try XCTUnwrap(ReviewedRuntimeDrillOverlay.compile(
            overlayData: fixture.overlayData, catalogData: fixture.catalogData,
            catalog: fixture.catalog, expectedLessonID: "overlay-test"))
        let lesson = try XCTUnwrap(fixture.catalog.lessons.first)
        let original = lesson.sourceTemplate().blocks
        let applied = try XCTUnwrap(overlay.applying(to: lesson, blocks: original))

        XCTAssertEqual(applied.first?.sourceActivityKey, "frontal_stance")
        var expected = original[0]
        expected.sourceActivityKey = "frontal_stance"
        XCTAssertEqual(applied[0], expected)
        XCTAssertEqual(applied[0].durationSeconds, 47)
        XCTAssertEqual(applied[0].restAfterSeconds, original[0].restAfterSeconds)
        XCTAssertEqual(applied[0].sourceTitle, "Original title")
        XCTAssertEqual(applied[0].sourceInstructions, "Original instructions")
    }

    func testOverlayRejectsIncompleteCoverageAndCatalogMismatch() throws {
        let incomplete = try overlayFixture(blockCount: 2, proposalCount: 1)
        let decoded = try XCTUnwrap(ReviewedRuntimeDrillOverlay.compile(
            overlayData: incomplete.overlayData, catalogData: incomplete.catalogData,
            catalog: incomplete.catalog, expectedLessonID: "overlay-test"))
        let lesson = try XCTUnwrap(incomplete.catalog.lessons.first)
        XCTAssertNil(decoded.applying(to: lesson, blocks: lesson.sourceTemplate().blocks))

        var changedCatalog = incomplete.catalogData
        changedCatalog.append(0x20)
        XCTAssertNil(ReviewedRuntimeDrillOverlay.compile(overlayData: incomplete.overlayData,
            catalogData: changedCatalog, catalog: incomplete.catalog, expectedLessonID: "overlay-test"))
    }

    func testOverlayRejectsAnyUnapprovedOrDuplicateTarget() throws {
        let fixture = try overlayFixture(blockCount: 1, approved: false)
        let overlay = try XCTUnwrap(ReviewedRuntimeDrillOverlay.compile(
            overlayData: fixture.overlayData, catalogData: fixture.catalogData,
            catalog: fixture.catalog, expectedLessonID: "overlay-test"))
        let lesson = try XCTUnwrap(fixture.catalog.lessons.first)
        XCTAssertNil(overlay.applying(to: lesson, blocks: lesson.sourceTemplate().blocks))

        let duplicate = try overlayFixture(blockCount: 2, proposalCount: 2, duplicateTarget: true)
        let duplicateOverlay = try XCTUnwrap(ReviewedRuntimeDrillOverlay.compile(
            overlayData: duplicate.overlayData, catalogData: duplicate.catalogData,
            catalog: duplicate.catalog, expectedLessonID: "overlay-test"))
        let duplicateLesson = try XCTUnwrap(duplicate.catalog.lessons.first)
        XCTAssertNil(duplicateOverlay.applying(to: duplicateLesson,
            blocks: duplicateLesson.sourceTemplate().blocks))
    }

    private func overlayFixture(blockCount: Int, proposalCount: Int? = nil,
                                approved: Bool = true, duplicateTarget: Bool = false) throws
        -> (catalogData: Data, catalog: WorkoutCatalog, overlayData: Data) {
        let blocks = (0..<blockCount).map { index in
            """
            {"id":"block-\(index)","title":"Original title\(index == 0 ? "" : " \(index)")","instructions":"Original instructions\(index == 0 ? "" : " \(index)")","kind":"boxing","rounds":1,"durationSeconds":47,"restSeconds":13,"completion":"timed"}
            """
        }.joined(separator: ",")
        let catalogData = Data("""
        {"schemaVersion":1,"workouts":[{"id":"overlay-test","program":"basic","week":1,"day":1,"title":"Overlay test","sourceURL":"https://example.test/workout","sourceSHA256":"\(String(repeating: "a", count: 64))","blocks":[\(blocks)]}]}
        """.utf8)
        let catalog = try WorkoutCatalog.load(catalogData)
        let hash = SHA256.hash(data: catalogData).map { String(format: "%02x", $0) }.joined()
        let review = RuntimeDrillProposal.Review(state: approved ? .approved : .unreviewed,
            reviewer: approved ? "reviewer@example.test" : nil,
            reviewedAt: approved ? Date(timeIntervalSince1970: 1_800_000_000) : nil)
        let count = proposalCount ?? blockCount
        let proposals = (0..<count).map { index -> RuntimeDrillProposal in
            let targetIndex = duplicateTarget ? 0 : index
            return RuntimeDrillProposal(schemaVersion: 1, proposalID: "overlay-\(index)",
                catalogSHA256: hash, sourceSHA256: String(repeating: "a", count: 64),
                target: .init(kind: .runtimeSegment, lessonID: "overlay-test",
                    sourceBlockID: "block-\(targetIndex)", sourceItemID: nil,
                    runtimeSegmentIndex: targetIndex),
                sourceTitle: targetIndex == 0 ? "Original title" : "Original title \(targetIndex)",
                sourceInstructions: targetIndex == 0 ? "Original instructions" : "Original instructions \(targetIndex)",
                sourceItemText: nil,
                runtimeTitle: targetIndex == 0 ? "Original title" : "Original title \(targetIndex)",
                runtimeInstructions: targetIndex == 0 ? "Original instructions" : "Original instructions \(targetIndex)",
                movementKey: "frontal_stance", movementVersion: "v1",
                measurementRecipe: .forExercise("frontal_stance"), review: review,
                measurementReview: review)
        }
        let overlay = ReviewedRuntimeDrillOverlay(schemaVersion: 1, catalogSHA256: hash,
            lessonID: "overlay-test", proposals: proposals)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (catalogData, catalog, try encoder.encode(overlay))
    }
}
