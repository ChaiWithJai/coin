import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from verify_source_catalog_freshness import verify_catalog


class SourceCatalogFreshnessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.catalog = Path(self.temp.name) / "WorkoutCatalog.json"

    @staticmethod
    def workout(workout_id, source_url, raw):
        return {
            "id": workout_id,
            "sourceURL": source_url,
            "sourceSHA256": hashlib.sha256(raw).hexdigest(),
        }

    def write(self, workouts):
        self.catalog.write_text(json.dumps({"catalogVersion": "fixture-v1", "workouts": workouts}))

    def test_full_match_fetches_each_canonical_trailing_slash_url(self):
        first, second = b"<html>one</html>", b"<html>two</html>"
        self.write([
            self.workout("one", "https://boxing.dharmicdata.org/program/basic/week/1/day/1", first),
            self.workout("two", "https://boxing.dharmicdata.org/program/basic/week/1/day/2/", second),
        ])
        calls = []
        responses = {
            "https://boxing.dharmicdata.org/program/basic/week/1/day/1/": first,
            "https://boxing.dharmicdata.org/program/basic/week/1/day/2/": second,
        }

        def fetch(url, timeout):
            calls.append((url, timeout))
            return responses[url]

        report = verify_catalog(self.catalog, fetch=fetch, timeout=3.5)
        self.assertTrue(report["passed"])
        self.assertEqual(report["matched_count"], 2)
        self.assertEqual(calls, [(url, 3.5) for url in responses])
        self.assertEqual(report["missing"], [])
        self.assertEqual(report["drift"], [])
        self.assertEqual(report["fetch_failures"], [])

    def test_raw_byte_drift_is_reported_without_rewriting_catalog(self):
        original = b"<html>original</html>"
        self.write([self.workout("one", "https://boxing.dharmicdata.org/workout", original)])
        before = self.catalog.read_bytes()
        report = verify_catalog(self.catalog, fetch=lambda _url, _timeout: b"<html>changed</html>")
        self.assertFalse(report["passed"])
        self.assertEqual([item["workout_id"] for item in report["drift"]], ["one"])
        self.assertNotEqual(report["drift"][0]["expected_sha256"], report["drift"][0]["actual_sha256"])
        self.assertEqual(self.catalog.read_bytes(), before)

    def test_fetch_failure_is_isolated_and_reported(self):
        raw = b"fixture"
        self.write([
            self.workout("broken", "https://boxing.dharmicdata.org/broken", raw),
            self.workout("healthy", "https://boxing.dharmicdata.org/healthy", raw),
        ])

        def fetch(url, _timeout):
            if url.endswith("/broken/"):
                raise TimeoutError("fixture secret must not leak")
            return raw

        report = verify_catalog(self.catalog, fetch=fetch)
        self.assertFalse(report["passed"])
        self.assertEqual(report["matched_count"], 1)
        self.assertEqual(report["fetch_failures"], [{
            "workout_id": "broken",
            "url": "https://boxing.dharmicdata.org/broken/",
            "error": "TimeoutError",
        }])

    def test_missing_provenance_is_reported_without_fetching(self):
        self.write([{"id": "missing", "sourceURL": "https://boxing.dharmicdata.org/missing"}])
        calls = []
        report = verify_catalog(self.catalog, fetch=lambda *args: calls.append(args))
        self.assertFalse(report["passed"])
        self.assertEqual(report["missing"][0]["fields"], ["sourceSHA256"])
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
