import json
import tempfile
import unittest
from pathlib import Path
from server.source_translation_batch import Store, ProposalResponseError, process_one, source_items, validate_proposal

CATALOG = json.loads((Path(__file__).resolve().parents[2] / "ios" / "WorkoutCatalog.json").read_text())

class TranslationBatchTests(unittest.TestCase):
    def test_manifest_numeric(self):
        items = source_items(CATALOG, "basic-w1-d1")
        self.assertEqual(len(items), 30)
        target = next(i for i in items if "4 ROUNDS OF 2 MINUTES" in i["sourceText"])
        with self.assertRaisesRegex(ValueError, "Numeric"):
            validate_proposal(target, {"proposedFrench": "3 rounds de 2 minutes", "ambiguityFlags": []})
        jump = next(i for i in source_items(CATALOG, "basic-w2-d1")
                    if i["sourceText"] == "12 JUMP SQUATS")
        proposed = validate_proposal(jump, {"proposedFrench": "12 sauts de genou", "ambiguityFlags": []})
        self.assertIn("jump_squat_term_missing", proposed["qualityWarnings"])
        fragment = next(i for i in source_items(CATALOG, "basic-w2-d1")
                        if i["sourceItemID"] == "p10-b48")
        self.assertEqual(fragment["sourceText"], "RAISES (MAX)")
        self.assertIn("HANGING LEG\nRAISES (MAX)", fragment["sectionContext"])

    def test_durable_coverage_attempt_and_cost(self):
        with tempfile.TemporaryDirectory() as root:
            store = Store(Path(root) / "batch.sqlite")
            job = store.submit_day(CATALOG, "basic-w1-d1", "model-v1")
            self.assertEqual(job, store.submit_day(CATALOG, "basic-w1-d1", "model-v1"))
            with self.assertRaisesRegex(ValueError, "incomplete"):
                store.export_day(job)
            claim = store.claim(job)
            store.finish(job, claim, {"proposedFrench": "0", "ambiguityFlags": []})
            with store.db() as db:
                failed = db.execute("SELECT * FROM attempts WHERE number=1").fetchone()
                self.assertEqual(failed["state"], "failed")
                self.assertEqual(json.loads(failed["response"])["proposedFrench"], "0")
                self.assertIsNone(failed["actual_cost_usd"])
            retry = store.claim(job)
            self.assertEqual(retry["number"], 2)
            store.finish(job, retry, {"proposedFrench": retry["item"]["sourceText"], "ambiguityFlags": ["Review"]}, usage={"prompt_tokens": 21})
            self.assertEqual(Store(store.path).status(job)["counts"]["done"], 1)
            self.assertNotEqual(job, store.submit_day(CATALOG, "basic-w1-d1", "model-v1",
                                                       "source-fr-proposal-v4-section-context"))

    def test_process_one(self):
        class Fake:
            def propose(self, item):
                return {"proposedFrench": item["sourceText"], "ambiguityFlags": ["Review"]}, {}
        with tempfile.TemporaryDirectory() as root:
            store = Store(Path(root) / "batch.sqlite")
            job = store.submit_day(CATALOG, "basic-w1-d1", "fake")
            self.assertEqual(process_one(store, job, Fake())["state"], "done")
            self.assertEqual(store.status(job)["counts"], {"done": 1, "pending": 29})

    def test_invalid_model_json_retains_raw_reply(self):
        class Fake:
            def propose(self, item):
                raise ProposalResponseError("Model reply was not valid proposal JSON",
                                            {"choices": [{"message": {"content": ""}}]},
                                            {"completion_tokens": 512})
        with tempfile.TemporaryDirectory() as root:
            store = Store(Path(root) / "batch.sqlite")
            job = store.submit_day(CATALOG, "basic-w1-d1", "fake")
            self.assertEqual(process_one(store, job, Fake())["state"], "failed")
            with store.db() as db:
                row = db.execute("SELECT response,completion_tokens FROM attempts").fetchone()
            self.assertEqual(json.loads(row["response"])["choices"][0]["message"]["content"], "")
            self.assertEqual(row["completion_tokens"], 512)

    def test_resume_rejects_changed_prompt_client(self):
        class WrongPrompt:
            prompt_version = "source-fr-proposal-v4-section-context"
            def propose(self, item):
                raise AssertionError("Must reject before inference")
        with tempfile.TemporaryDirectory() as root:
            store = Store(Path(root) / "batch.sqlite")
            job = store.submit_day(CATALOG, "basic-w1-d1", "fake")
            with self.assertRaisesRegex(ValueError, "prompt version"):
                process_one(store, job, WrongPrompt())
            self.assertEqual(store.status(job)["attempts"], 0)

if __name__ == "__main__":
    unittest.main()
