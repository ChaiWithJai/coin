import json
import tempfile
import unittest
from pathlib import Path

from app import atomic_write, item_key, load_labels, load_source, queue_sha256


class ActivityReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "queue.json"
        self.item = {"workout_id": "basic-w1-d1", "source_block_id": "block",
                     "proposal_activity": "unknown", "source_text": "STANCE DRILL",
                     "source_text_sha256": "source-hash"}
        self.source = {"schema_version": 1, "job_id": "job", "count": 1,
                       "evidence_status": "stored_model_proposals_for_review_not_labels",
                       "items": [self.item]}
        self.path.write_text(json.dumps(self.source))

    def tearDown(self):
        self.tmp.cleanup()

    def test_load_and_persist_labels_bound_to_exact_queue(self):
        source = load_source(self.path)
        self.assertEqual(item_key(source["items"][0]), "basic-w1-d1::block")
        labels_path = self.path.with_name("labels.json")
        labels = load_labels(labels_path, source)
        self.assertFalse(labels["runtimeEligible"])
        self.assertEqual(labels["queueSHA256"], queue_sha256(source))
        labels["labels"][item_key(self.item)] = {"decision": "defer", "notes": "needs coach"}
        atomic_write(labels_path, labels)
        self.assertEqual(load_labels(labels_path, source)["labels"][item_key(self.item)]["decision"], "defer")

    def test_queue_drift_rejects_existing_labels(self):
        source = load_source(self.path)
        labels_path = self.path.with_name("labels.json")
        atomic_write(labels_path, load_labels(labels_path, source))
        source["items"][0]["source_text"] = "CHANGED"
        source["items"][0]["source_text_sha256"] = "changed-hash"
        with self.assertRaisesRegex(ValueError, "exact review queue"):
            load_labels(labels_path, source)

    def test_known_proposals_and_atomic_items_are_reviewable(self):
        bad = dict(self.source)
        bad["items"] = [dict(self.item, proposal_activity="boxing", source_item_id="one"),
                        dict(self.item, proposal_activity="footwork", source_item_id="two")]
        bad["count"] = 2
        self.path.write_text(json.dumps(bad))
        loaded = load_source(self.path)
        self.assertEqual([item_key(item) for item in loaded["items"]],
                         ["basic-w1-d1::block::one", "basic-w1-d1::block::two"])

    def test_duplicate_atomic_identity_is_rejected(self):
        bad = dict(self.source)
        bad["items"] = [dict(self.item, source_item_id="one"),
                        dict(self.item, source_item_id="one")]
        bad["count"] = 2
        self.path.write_text(json.dumps(bad))
        with self.assertRaisesRegex(ValueError, "Invalid"):
            load_source(self.path)


if __name__ == "__main__":
    unittest.main()
