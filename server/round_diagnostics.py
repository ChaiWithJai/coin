"""Candidate observation counts for an accepted round, without technique claims."""

from round_harness import reset_status


def summarize_round_candidates(summary):
    """Summarize phone-supplied exchange candidates and reset observability.

    The accepted round schema contains ``exchanges``. Legacy null reset values
    remain unobservable under the same evidence gate used by the report.
    """
    exchanges = summary["exchanges"]
    counts = {"observed": 0, "not_detected": 0, "unobservable": 0}
    for exchange in exchanges:
        counts[reset_status(exchange)] += 1
    return {
        "candidate_exchange_count": len(exchanges),
        "reset_evidence_counts": counts,
        "evidence": "phone_pose_candidates_not_verified_technique",
    }
