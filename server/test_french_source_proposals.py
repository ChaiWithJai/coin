import json
import unittest

from french_source_proposals import CATALOG, OUTPUT, PROPOSALS, build, numbers


class FrenchSourceProposalTests(unittest.TestCase):
    def test_artifact_matches_catalog_and_stays_unreviewed(self):
        generated = build(json.loads(CATALOG.read_text()))
        self.assertEqual(generated, json.loads(OUTPUT.read_text()))
        self.assertFalse(generated["runtimeEligible"])
        self.assertEqual(len(generated["items"]), len(PROPOSALS))
        self.assertTrue(all(item["reviewStatus"] == "unreviewed" for item in generated["items"]))

    def test_prescription_digits_are_preserved(self):
        for item in build(json.loads(CATALOG.read_text()))["items"]:
            self.assertEqual(numbers(item["sourceText"]), numbers(item["proposedFrench"]))

    def test_changed_source_fails_closed(self):
        catalog = json.loads(CATALOG.read_text())
        block = next(b for b in catalog["workouts"][0]["blocks"] if b["id"] == "basic-w1-d1-p3-s3-1")
        block["sourceItems"][1]["text"] = "5 ROUNDS"
        with self.assertRaisesRegex(ValueError, "Source wording changed"):
            build(catalog)


if __name__ == "__main__":
    unittest.main()
