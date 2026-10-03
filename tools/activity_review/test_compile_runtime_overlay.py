import copy
import hashlib
import json
import unittest

from app import item_key, queue_sha256
from compile_runtime_overlay import compile_overlay, decision_sha256


class CompileRuntimeOverlayTests(unittest.TestCase):
    def setUp(self):
        self.catalog = {"schemaVersion": 1, "workouts": [{"id": "basic-w1-d1",
            "sourceSHA256": "a" * 64, "blocks": [{"id": "block-1", "title": "Squat work",
            "instructions": "Do controlled squats",
            "sourceItems": [{"id": "item-1", "text": "10 SQUATS"}]}]}]}
        self.catalog_data = json.dumps(self.catalog, separators=(",", ":")).encode()
        self.catalog_hash = hashlib.sha256(self.catalog_data).hexdigest()
        self.item = {"workout_id": "basic-w1-d1", "source_block_id": "block-1",
                     "source_item_id": "item-1", "proposal_activity": "squats",
                     "source_text": "10 SQUATS", "source_text_sha256": "b" * 64}
        self.source = {"schema_version": 1, "job_id": "job", "count": 1,
            "evidence_status": "stored_model_proposals_for_review_not_labels", "items": [self.item]}
        self.key = item_key(self.item)
        self.label = {"decision": "pass", "notes": "", "sourceTextSHA256": "b" * 64,
            "proposalActivity": "squats", "reviewKind": "local_reviewer_decision_not_promotion"}
        self.labels = {"schemaVersion": 1, "purpose": "activity_proposal_review",
            "runtimeEligible": False, "jobID": "job", "queueSHA256": queue_sha256(self.source),
            "labels": {self.key: self.label}}
        self.manifest = {"schema_version": 1, "purpose": "coin_runtime_segment_manifest",
            "catalog_sha256": self.catalog_hash, "lesson_id": "basic-w1-d1", "source_sha256": "a" * 64,
            "segments": [{"runtime_segment_index": 0, "source_block_id": "block-1",
                "source_item_id": "item-1", "runtime_title": "10 SQUATS",
                "runtime_instructions": "Do controlled squats"}]}
        self.approval = {"schema_version": 1, "purpose": "runtime_drill_human_approval",
            "queue_sha256": queue_sha256(self.source), "catalog_sha256": self.catalog_hash,
            "lesson_id": "basic-w1-d1", "reviewer": "coach@example.test",
            "reviewed_at": "2026-10-03T05:00:00Z", "approvals": {self.key: {
                "decision_sha256": decision_sha256(self.label), "proposal_approved": True,
                "measurement_approved": True}}}

    def compile(self):
        return compile_overlay(self.source, self.labels, self.approval, self.manifest, self.catalog_data)

    def test_compiles_exact_approved_review_to_versioned_runtime_segment(self):
        proposal = self.compile()["proposals"][0]
        self.assertEqual(proposal["target"]["runtimeSegmentIndex"], 0)
        self.assertEqual(proposal["movementKey"], "squats")
        self.assertEqual(proposal["measurementRecipe"], {"id": "mediapipe-squat-angle",
            "version": "v1", "capability": "rep_candidate", "validationStatus": "unvalidated"})
        self.assertEqual(proposal["review"]["reviewer"], "coach@example.test")

    def test_correction_uses_structured_source_grounded_activity(self):
        self.label["decision"] = "fail"
        self.label["notes"] = json.dumps({"activity": "squat_jumps", "evidence_quote": "SQUATS"})
        self.approval["approvals"][self.key]["decision_sha256"] = decision_sha256(self.label)
        proposal = self.compile()["proposals"][0]
        self.assertEqual(proposal["movementKey"], "squat_jumps")
        self.assertEqual(proposal["measurementRecipe"]["id"], "session-clock")

    def test_rejects_unsigned_changed_or_single_axis_approval(self):
        for field, value in [("proposal_approved", False), ("measurement_approved", False),
                             ("decision_sha256", "0" * 64)]:
            approval = copy.deepcopy(self.approval)
            approval["approvals"][self.key][field] = value
            with self.assertRaisesRegex(ValueError, "both exact"):
                compile_overlay(self.source, self.labels, approval, self.manifest, self.catalog_data)

    def test_rejects_deferred_stale_and_partial_inputs(self):
        bad = copy.deepcopy(self.labels)
        bad["labels"][self.key]["decision"] = "defer"
        with self.assertRaisesRegex(ValueError, "both exact"):
            compile_overlay(self.source, bad, self.approval, self.manifest, self.catalog_data)
        approval = copy.deepcopy(self.approval)
        approval["approvals"][self.key]["decision_sha256"] = decision_sha256(bad["labels"][self.key])
        with self.assertRaisesRegex(ValueError, "open or deferred"):
            compile_overlay(self.source, bad, approval, self.manifest, self.catalog_data)
        manifest = copy.deepcopy(self.manifest)
        manifest["catalog_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "exact catalog"):
            compile_overlay(self.source, self.labels, self.approval, manifest, self.catalog_data)
        manifest = copy.deepcopy(self.manifest)
        manifest["segments"][0]["source_item_id"] = "missing-item"
        with self.assertRaisesRegex(ValueError, "unknown source item"):
            compile_overlay(self.source, self.labels, self.approval, manifest, self.catalog_data)

    def test_rejects_abstract_runtime_activity(self):
        self.item["proposal_activity"] = "conditioning"
        self.label["proposalActivity"] = "conditioning"
        self.approval["queue_sha256"] = queue_sha256(self.source)
        self.approval["approvals"][self.key]["decision_sha256"] = decision_sha256(self.label)
        with self.assertRaisesRegex(ValueError, "concrete registered"):
            self.compile()


if __name__ == "__main__":
    unittest.main()
