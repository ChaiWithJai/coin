import hashlib
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "evidence" / "workout-delivery-20261003" / "source-documents"


class LinkedRunSourceEvidenceTests(unittest.TestCase):
    def test_extracted_text_matches_immutable_manifest(self):
        manifest = json.loads((SOURCE_DIR / "manifest.json").read_text())
        self.assertEqual(manifest["schema_version"], 1)
        self.assertEqual(len(manifest["documents"]), 2)
        for document in manifest["documents"]:
            payload = (SOURCE_DIR / document["text_path"]).read_bytes()
            self.assertEqual(hashlib.sha256(payload).hexdigest(), document["text_sha256"])
            self.assertRegex(document["docx_sha256"], r"^[0-9a-f]{64}$")
            self.assertIn(document["document_id"], document["source_url"])
            self.assertIn(document["document_id"], document["export_url"])

    def test_exact_prescriptions_remain_present(self):
        steady = (SOURCE_DIR / "steady-state-running-workout.txt").read_text()
        self.assertIn("around 135-145 heart beat rate) for 30 minutes with no breaks", steady)
        self.assertIn("3 rounds of 3 minutes with one minute of rest", steady)
        interval = (SOURCE_DIR / "interval-running-workout.txt").read_text()
        self.assertIn("3-6 rounds of interval running", interval)
        self.assertEqual(interval.count("3 minutes of running at a fast pace"), 6)
        self.assertEqual(interval.count("100-meter sprint"), 3)
        self.assertIn("RestT: 1 minute of light jogging", interval)
        self.assertIn("Res: 1.5 - 2 minutes of walking", interval)
        self.assertIn("Resr: 1 minute of walking", interval)


if __name__ == "__main__":
    unittest.main()
