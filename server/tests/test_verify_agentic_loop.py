import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from verify_agentic_loop import VerificationError, verify


class AgenticLoopVerifierTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name, value):
        path = self.root / name
        if isinstance(value, bytes):
            path.write_bytes(value)
        else:
            path.write_text(json.dumps(value, sort_keys=True), encoding="utf-8")
        return {"path": name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

    def manifest(self, mode="program"):
        record = self.write("record.json", {"sessions": [
            {"session_id": "session-train", "mode": mode, "observations": [{"id": "observation-1"}]},
            {"session_id": "session-eval", "mode": mode, "observations": [{"id": "observation-2"}]}]})
        review = self.write("review.json", {"decisions": [
            {"review_id": "review-1", "session_id": "session-train", "observation_id": "observation-1",
             "state": "corrected", "correction": {"label": "quiet"}},
            {"review_id": "review-2", "session_id": "session-eval", "observation_id": "observation-2",
             "state": "accepted"}]})
        dataset = self.write("dataset.json", {"examples": [
            {"source_review_id": "review-1", "session_id": "session-train", "split": "train"},
            {"source_review_id": "review-2", "session_id": "session-eval", "split": "eval"}]})
        artifact = self.write("candidate.bin", b"candidate-v1")
        evaluation = self.write("evaluation.json", {"artifact_sha256": artifact["sha256"],
                                "held_out_session_ids": ["session-eval"], "passed": True})
        deployment = self.write("deployment.json", {"mode": mode, "artifact_sha256": artifact["sha256"],
                                "evaluation_sha256": evaluation["sha256"]})
        body = {"mode": mode, "record": record, "review": review, "dataset": dataset,
                "model_artifact": artifact, "evaluation": evaluation, "deployment": deployment}
        path = self.root / "manifest.json"
        path.write_text(json.dumps(body), encoding="utf-8")
        return path, body

    def test_verifies_program_and_freestyle_cycles(self):
        for mode in ("program", "freestyle"):
            with self.subTest(mode=mode):
                path, _ = self.manifest(mode)
                result = verify(path)
                self.assertTrue(result["verified"])
                self.assertEqual(result["mode"], mode)
                self.assertEqual(result["held_out_sessions"], ["session-eval"])

    def test_rejects_training_and_evaluation_session_leakage(self):
        path, body = self.manifest()
        record_path = self.root / body["record"]["path"]
        record = json.loads(record_path.read_text())
        record["sessions"] = [{"session_id": "session-train", "mode": "program", "observations": [
            {"id": "observation-1"}, {"id": "observation-2"}]}]
        record_path.write_text(json.dumps(record), encoding="utf-8")
        body["record"]["sha256"] = hashlib.sha256(record_path.read_bytes()).hexdigest()
        review_path = self.root / body["review"]["path"]
        review = json.loads(review_path.read_text())
        review["decisions"][1]["session_id"] = "session-train"
        review_path.write_text(json.dumps(review), encoding="utf-8")
        body["review"]["sha256"] = hashlib.sha256(review_path.read_bytes()).hexdigest()
        dataset_path = self.root / body["dataset"]["path"]
        dataset = json.loads(dataset_path.read_text())
        dataset["examples"][1]["session_id"] = "session-train"
        dataset_path.write_text(json.dumps(dataset), encoding="utf-8")
        body["dataset"]["sha256"] = hashlib.sha256(dataset_path.read_bytes()).hexdigest()
        path.write_text(json.dumps(body), encoding="utf-8")
        with self.assertRaisesRegex(VerificationError, "both train and eval"):
            verify(path)

    def test_rejects_unreviewed_data_and_changed_deployment_artifact(self):
        path, body = self.manifest()
        dataset_path = self.root / body["dataset"]["path"]
        dataset = json.loads(dataset_path.read_text())
        dataset["examples"][0]["source_review_id"] = "model-proposal"
        dataset_path.write_text(json.dumps(dataset), encoding="utf-8")
        body["dataset"]["sha256"] = hashlib.sha256(dataset_path.read_bytes()).hexdigest()
        path.write_text(json.dumps(body), encoding="utf-8")
        with self.assertRaisesRegex(VerificationError, "unapproved review"):
            verify(path)

        path, body = self.manifest()
        deployment_path = self.root / body["deployment"]["path"]
        deployment = json.loads(deployment_path.read_text())
        deployment["artifact_sha256"] = "0" * 64
        deployment_path.write_text(json.dumps(deployment), encoding="utf-8")
        body["deployment"]["sha256"] = hashlib.sha256(deployment_path.read_bytes()).hexdigest()
        path.write_text(json.dumps(body), encoding="utf-8")
        with self.assertRaisesRegex(VerificationError, "not the evaluated artifact"):
            verify(path)

    def test_rejects_mutated_artifact_before_inspecting_claims(self):
        path, body = self.manifest()
        (self.root / body["model_artifact"]["path"]).write_bytes(b"mutated")
        with self.assertRaisesRegex(VerificationError, "sha256 mismatch"):
            verify(path)


if __name__ == "__main__":
    unittest.main()
