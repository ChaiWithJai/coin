import unittest

from round_diagnostics import summarize_round_candidates


class RoundDiagnosticsTests(unittest.TestCase):
    def test_legacy_null_is_unobservable(self):
        summary = {"exchanges": [{"id": 1, "resetMs": None}]}
        self.assertEqual(summarize_round_candidates(summary), {
            "candidate_exchange_count": 1,
            "reset_evidence_counts": {"observed": 0, "not_detected": 0, "unobservable": 1},
            "evidence": "phone_pose_candidates_not_verified_technique",
        })

    def test_validated_reset_evidence_and_measured_reset(self):
        summary = {"exchanges": [
            {"id": 1, "resetMs": 320},
            {"id": 2, "resetMs": None, "resetEvidence": {
                "version": "pose-reset-observability-v1", "status": "not_detected",
                "windowDurationMs": 500, "observedDurationMs": 500}},
            {"id": 3, "resetMs": None, "resetEvidence": {
                "version": "pose-reset-observability-v1", "status": "not_detected",
                "windowDurationMs": 500, "observedDurationMs": 300}},
        ]}
        result = summarize_round_candidates(summary)
        self.assertEqual(result["candidate_exchange_count"], 3)
        self.assertEqual(result["reset_evidence_counts"], {
            "observed": 1, "not_detected": 1, "unobservable": 1,
        })


if __name__ == "__main__":
    unittest.main()
