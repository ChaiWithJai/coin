import json
import tempfile
import unittest
from pathlib import Path

from app import item_key, queue_sha256
from compile_dataset import compile_files, compile_review


class CompileDatasetTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.items = [self.item("train-day", "block-1", "STANCE DRILL"),
                      self.item("eval-day", "block-2", "JUMP SQUATS")]
        self.source = {"schema_version": 1, "job_id": "job", "count": 2,
                       "evidence_status": "stored_model_proposals_for_review_not_labels",
                       "items": self.items}
        self.labels = {"schemaVersion": 1, "purpose": "activity_proposal_review",
                       "runtimeEligible": False, "jobID": "job",
                       "queueSHA256": queue_sha256(self.source), "labels": {}}

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def item(workout, block, text):
        return {"workout_id": workout, "source_block_id": block,
                "proposal_activity": "unknown", "source_text": text,
                "source_text_sha256": f"hash-{block}"}

    def label(self, item, decision, notes=""):
        self.labels["labels"][item_key(item)] = {
            "decision": decision, "notes": notes,
            "sourceTextSHA256": item["source_text_sha256"],
            "proposalActivity": "unknown",
            "reviewKind": "local_reviewer_decision_not_promotion",
        }

    def test_emits_verifier_shapes_and_keeps_sessions_isolated(self):
        self.label(self.items[0], "pass")
        self.label(self.items[1], "fail", json.dumps({
            "activity": "squat_jumps", "evidence_quote": "JUMP SQUATS"}))
        record, review, dataset = compile_review(self.source, self.labels, {"eval-day"})
        self.assertEqual({s["session_id"] for s in record["sessions"]},
                         {"source-workout:train-day", "source-workout:eval-day"})
        self.assertEqual([d["state"] for d in review["decisions"]], ["accepted", "corrected"])
        self.assertEqual(review["decisions"][1]["correction"]["activity"], "squat_jumps")
        split_by_session = {e["session_id"]: e["split"] for e in dataset["examples"]}
        self.assertEqual(split_by_session["source-workout:train-day"], "train")
        self.assertEqual(split_by_session["source-workout:eval-day"], "eval")
        self.assertFalse(dataset["training_performed"])

    def test_rejects_open_deferred_and_unstructured_corrections(self):
        self.label(self.items[0], "pass")
        with self.assertRaisesRegex(ValueError, "unreviewed"):
            compile_review(self.source, self.labels, {"eval-day"})
        self.label(self.items[1], "defer", "needs coach")
        with self.assertRaisesRegex(ValueError, "deferred"):
            compile_review(self.source, self.labels, {"eval-day"})
        self.label(self.items[1], "fail", "looks like squat jumps")
        with self.assertRaisesRegex(ValueError, "require JSON"):
            compile_review(self.source, self.labels, {"eval-day"})

    def test_rejects_non_source_quote_and_cross_split_setup(self):
        self.label(self.items[0], "pass")
        self.label(self.items[1], "fail", json.dumps({
            "activity": "squat_jumps", "evidence_quote": "NOT IN SOURCE"}))
        with self.assertRaisesRegex(ValueError, "exact nonempty"):
            compile_review(self.source, self.labels, {"eval-day"})
        with self.assertRaisesRegex(ValueError, "both train and eval"):
            compile_review(self.source, self.labels, {"train-day", "eval-day"})

    def test_rejects_unregistered_but_well_formed_movement_key(self):
        self.label(self.items[0], "pass")
        self.label(self.items[1], "fail", json.dumps({
            "activity": "invented_jump", "evidence_quote": "JUMP SQUATS"}))
        with self.assertRaisesRegex(ValueError, "registered movement key"):
            compile_review(self.source, self.labels, {"eval-day"})

    def test_rejects_labels_outside_queue_and_invalid_provenance(self):
        self.label(self.items[0], "pass")
        self.label(self.items[1], "pass")
        self.labels["labels"]["other::block"] = dict(self.labels["labels"][item_key(self.items[0])])
        with self.assertRaisesRegex(ValueError, "outside the exact queue"):
            compile_review(self.source, self.labels, {"eval-day"})
        self.labels["labels"].pop("other::block")
        self.labels["labels"][item_key(self.items[0])]["reviewKind"] = "model_review"
        with self.assertRaisesRegex(ValueError, "review provenance"):
            compile_review(self.source, self.labels, {"eval-day"})

    def test_files_remain_bound_to_exact_queue(self):
        self.label(self.items[0], "pass")
        self.label(self.items[1], "pass")
        queue, labels, out = self.root / "queue.json", self.root / "labels.json", self.root / "out"
        queue.write_text(json.dumps(self.source))
        labels.write_text(json.dumps(self.labels))
        result = compile_files(queue, labels, out, {"eval-day"})
        self.assertEqual(result["examples"], 2)
        self.assertTrue((out / "record.json").is_file())
        self.assertTrue((out / "review.json").is_file())
        self.assertTrue((out / "dataset.json").is_file())
        changed = dict(self.source)
        changed["items"] = [dict(item) for item in self.items]
        changed["items"][0]["source_text"] = "CHANGED"
        queue.write_text(json.dumps(changed))
        with self.assertRaisesRegex(ValueError, "exact review queue"):
            compile_files(queue, labels, out, {"eval-day"})


if __name__ == "__main__":
    unittest.main()
