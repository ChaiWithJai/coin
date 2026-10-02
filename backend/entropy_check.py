"""Measure sources of product entropy and enforce non-growth ratchets.

This is an architecture check, not a quality evaluator. Human boxing labels and
physical-device evidence remain separate promotion requirements.
"""
from collections import defaultdict
from pathlib import Path
import argparse
import json
import re

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "coin" / "ios"
BASELINE = {
    # Existing inline bilingual branches are technical debt. New ones fail the ratchet.
    "maximum_inline_language_branches": 34,
    "maximum_runtime_drill_libraries": 2,
    "maximum_fast_policy_models_promoted": 1,
}


def language_metrics():
    swift = list(IOS.glob("*.swift"))
    inline = sum(p.read_text().count("french ?") for p in swift)
    backend = (ROOT / "coin" / "backend" / "drills.py").read_text()
    app = (IOS / "CoachingCopy.swift").read_text()
    keys = re.findall(r"^\s*'([^']+)':\{", backend, re.MULTILINE)
    parity = all(app.count(f'"{key}"') >= 1 for key in keys)
    return {
        "inline_language_branches": inline,
        "inline_branch_budget": BASELINE["maximum_inline_language_branches"],
        "drill_keys": keys,
        "backend_ios_drill_key_parity": parity,
        "source_of_truth": "duplicated_python_and_swift",
    }


def telemetry_metrics():
    import mlflow
    from mlflow import MlflowClient
    mlflow.set_tracking_uri("http://127.0.0.1:5210")
    client = MlflowClient()
    runs = client.search_runs(["40"], max_results=1000)
    events = defaultdict(list)
    for run in runs:
        event_id = run.data.tags.get("event_id")
        if event_id:
            events[event_id].append(run)
    recovered = sum(
        any(r.info.status == "FINISHED" for r in attempts)
        and any(r.info.status == "FAILED" for r in attempts)
        for attempts in events.values()
    )
    unresolved = sum(
        not any(r.info.status == "FINISHED" for r in attempts)
        for attempts in events.values()
    )
    return {
        "unique_events": len(events),
        "events_finished": len(events) - unresolved,
        "events_unresolved": unresolved,
        "events_recovered_after_export_failure": recovered,
        "failed_export_attempt_runs": sum(
            r.info.status == "FAILED" for attempts in events.values() for r in attempts
        ),
        "rule": "Report reliability by unique event ID, not raw MLflow run status counts.",
    }


def evidence_metrics():
    return {
        "coach_reviewed_exchange_labels": 0,
        "physical_iphone_live_sessions": 0,
        "laya_synthetic_cases": 3,
        "compact_bonsai_checkpoint_pinned": False,
        "compact_bonsai_live_benchmark_complete": False,
        "resident_27b_vision_verified": False,
        "resident_27b_modality": "text_only",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true", help="Check source ratchets without MLflow telemetry")
    args = parser.parse_args()
    language = language_metrics()
    telemetry = {"status": "not_checked_offline"} if args.offline else telemetry_metrics()
    evidence = evidence_metrics()
    violations = []
    if language["inline_language_branches"] > language["inline_branch_budget"]:
        violations.append("inline_language_branches_grew")
    if not language["backend_ios_drill_key_parity"]:
        violations.append("drill_keys_drifted")
    report = {
        "version": "entropy-check-v1",
        "scope": "source_only" if args.offline else "source_and_telemetry",
        "language": language,
        "telemetry": telemetry,
        "evidence": evidence,
        "ratchet_violations": violations,
        "ratchet_passed": not violations,
    }
    print(json.dumps(report, indent=2))
    if violations:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
