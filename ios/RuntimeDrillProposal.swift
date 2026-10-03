import Foundation

/// A review artifact may propose runtime metadata, but it never edits source copy.
/// Promotion is deliberately a pure operation over a pinned catalog snapshot.
struct RuntimeDrillProposal: Codable, Equatable {
    static let currentSchemaVersion = 1

    enum TargetKind: String, Codable { case sourceItem = "source_item", runtimeSegment = "runtime_segment" }
    enum ReviewState: String, Codable { case unreviewed, approved, rejected }

    struct Target: Codable, Equatable {
        let kind: TargetKind
        let lessonID: String
        let sourceBlockID: String
        let sourceItemID: String?
        /// Required only for an expanded runtime segment. This is the stable
        /// zero-based position produced by WorkoutLesson.template().
        let runtimeSegmentIndex: Int?
    }

    struct Review: Codable, Equatable {
        let state: ReviewState
        let reviewer: String?
        let reviewedAt: Date?
    }

    let schemaVersion: Int
    let proposalID: String
    let catalogSHA256: String
    let sourceSHA256: String
    let target: Target

    // Exact source snapshots are guards, not replacement copy.
    let sourceTitle: String
    let sourceInstructions: String
    let sourceItemText: String?
    let runtimeTitle: String?
    let runtimeInstructions: String?

    let movementKey: String
    let movementVersion: String
    let measurementRecipe: ActivityMeasurementRecipe
    let review: Review
    let measurementReview: Review
}

struct PromotedRuntimeDrill: Equatable {
    let proposalID: String
    let lessonID: String
    let sourceBlockID: String
    let sourceItemID: String?
    let runtimeSegmentIndex: Int?
    let movementKey: String
    let movementVersion: String
    let measurementRecipe: ActivityMeasurementRecipe
}

enum RuntimeDrillAbstention: String, Equatable {
    case unsupportedSchema = "unsupported_schema"
    case invalidProposalID = "invalid_proposal_id"
    case invalidCatalogHash = "invalid_catalog_hash"
    case invalidSourceHash = "invalid_source_hash"
    case proposalNotApproved = "proposal_not_approved"
    case measurementNotApproved = "measurement_not_approved"
    case incompleteReview = "incomplete_review"
    case lessonNotFound = "lesson_not_found"
    case sourceHashMismatch = "source_hash_mismatch"
    case sourceBlockNotFound = "source_block_not_found"
    case sourceItemNotFound = "source_item_not_found"
    case targetNotAtomic = "target_not_atomic"
    case sourceWordingMismatch = "source_wording_mismatch"
    case runtimeSegmentNotFound = "runtime_segment_not_found"
    case runtimeLineageMismatch = "runtime_lineage_mismatch"
    case movementNotRegistered = "movement_not_registered"
    case movementVersionMismatch = "movement_version_mismatch"
    case measurementRecipeMismatch = "measurement_recipe_mismatch"
}

enum RuntimeDrillPromotion: Equatable {
    case promoted(PromotedRuntimeDrill)
    case abstained(RuntimeDrillAbstention)
}

enum RuntimeDrillCompiler {
    /// Compiles one proposal without mutating the catalog or a session plan.
    /// The caller must hash the exact catalog bytes it loaded and provide that
    /// digest; accepting a proposal never depends on filesystem scan order.
    static func promote(_ proposal: RuntimeDrillProposal, catalog: WorkoutCatalog,
                        catalogSHA256: String) -> RuntimeDrillPromotion {
        func abstain(_ reason: RuntimeDrillAbstention) -> RuntimeDrillPromotion { .abstained(reason) }
        guard proposal.schemaVersion == RuntimeDrillProposal.currentSchemaVersion else {
            return abstain(.unsupportedSchema)
        }
        guard proposal.proposalID.range(of: "^[a-z0-9][a-z0-9._-]{0,127}$", options: .regularExpression) != nil else {
            return abstain(.invalidProposalID)
        }
        guard validSHA256(proposal.catalogSHA256), proposal.catalogSHA256 == catalogSHA256 else {
            return abstain(.invalidCatalogHash)
        }
        guard validSHA256(proposal.sourceSHA256) else { return abstain(.invalidSourceHash) }
        guard proposal.review.state == .approved else { return abstain(.proposalNotApproved) }
        guard proposal.measurementReview.state == .approved else { return abstain(.measurementNotApproved) }
        guard complete(proposal.review), complete(proposal.measurementReview) else {
            return abstain(.incompleteReview)
        }
        guard let lesson = catalog.lessons.first(where: { $0.id == proposal.target.lessonID }) else {
            return abstain(.lessonNotFound)
        }
        guard lesson.sourceSHA256 == proposal.sourceSHA256 else { return abstain(.sourceHashMismatch) }
        guard let source = lesson.blocks.first(where: { $0.id == proposal.target.sourceBlockID }) else {
            return abstain(.sourceBlockNotFound)
        }
        guard source.title == proposal.sourceTitle, source.instructions == proposal.sourceInstructions else {
            return abstain(.sourceWordingMismatch)
        }

        switch proposal.target.kind {
        case .sourceItem:
            guard proposal.target.runtimeSegmentIndex == nil, let itemID = proposal.target.sourceItemID else {
                return abstain(.targetNotAtomic)
            }
            guard let item = source.sourceItems?.first(where: { $0.id == itemID }) else {
                return abstain(.sourceItemNotFound)
            }
            guard item.text == proposal.sourceItemText else { return abstain(.sourceWordingMismatch) }
        case .runtimeSegment:
            guard proposal.sourceItemText == nil, let index = proposal.target.runtimeSegmentIndex,
                  lesson.template().blocks.indices.contains(index) else {
                return abstain(.targetNotAtomic)
            }
            let segment = lesson.template().blocks[index]
            guard segment.sourceBlockID == source.id,
                  segment.sourceItemID == proposal.target.sourceItemID else {
                return abstain(.runtimeLineageMismatch)
            }
            guard segment.sourceTitle == proposal.runtimeTitle,
                  segment.sourceInstructions == proposal.runtimeInstructions else {
                return abstain(.sourceWordingMismatch)
            }
        }

        guard let movement = WorkoutMovementDefinition.forKey(proposal.movementKey) else {
            return abstain(.movementNotRegistered)
        }
        guard movement.version == proposal.movementVersion else { return abstain(.movementVersionMismatch) }
        guard ActivityMeasurementRecipe.forExercise(movement.key) == proposal.measurementRecipe else {
            return abstain(.measurementRecipeMismatch)
        }
        return .promoted(.init(proposalID: proposal.proposalID, lessonID: lesson.id,
            sourceBlockID: source.id, sourceItemID: proposal.target.sourceItemID,
            runtimeSegmentIndex: proposal.target.runtimeSegmentIndex, movementKey: movement.key,
            movementVersion: movement.version, measurementRecipe: proposal.measurementRecipe))
    }

    private static func validSHA256(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private static func complete(_ review: RuntimeDrillProposal.Review) -> Bool {
        guard let reviewer = review.reviewer?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !reviewer.isEmpty && review.reviewedAt != nil
    }
}
