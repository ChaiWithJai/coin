"""Synthetic contract probe for the pinned Bonsai 27B service.

Never use this fixture as a human-labeled result or training target.
"""
import json
import os
import time
import urllib.request
from pathlib import Path

import mlflow

from round_report import AcceptedAttempt, ReportProposal, validate_proposal

ROOT = Path(__file__).resolve().parents[3]
ATTEMPTS = [
    AcceptedAttempt(attempt_id="synthetic-round1-a", protocol_id="probe-combine-angle-v1",
                    accepted_by_boxer=True, start_ms=5000, end_ms=8600,
                    observed_phases=["initiate", "interact"],
                    correction="I could not verify an angle exit."),
    AcceptedAttempt(attempt_id="synthetic-round1-b", protocol_id="probe-combine-angle-v1",
                    accepted_by_boxer=True, start_ms=14000, end_ms=17600,
                    observed_phases=["initiate", "interact", "terminate"],
                    correction="I reset late; the feet were out of frame."),
]


def probe(endpoint: str, language: str = "en") -> dict:
    manifest = json.loads((Path(__file__).parent / "model-manifest.json").read_text())
    evidence = [attempt.model_dump() for attempt in ATTEMPTS]
    system = (
        "You are testing a boxing round-report schema on SYNTHETIC data. Return only JSON with exactly "
        "observation, interpretation, next_constraint_id, prediction, evidence_attempt_ids. "
        "Cite only supplied attempt IDs. Do not claim punch contact, successful angle exits, or visual foot evidence. "
        "Allowed next_constraint_id: probe_then_commit, exit_and_reset, repeat_and_review. "
        "Select one next-round constraint. Use one short sentence per text field, at most 120 characters each. "
        "Observation and prediction must be specific to supplied phases and uncertainty. No explanations outside the JSON. "
        f"Use {'French' if language == 'fr' else 'English'}."
    )
    body = {"model": manifest["model_alias"], "temperature": 0, "max_tokens": 384,
            "chat_template_kwargs": {"enable_thinking": False},
            "response_format": {"type": "json_object"},
            "messages": [{"role": "system", "content": system},
                         {"role": "user", "content": json.dumps({"source_kind": "synthetic_fixture",
                                                               "accepted_attempts": evidence})}]}
    mlflow.set_tracking_uri(os.getenv("MLFLOW_TRACKING_URI", "http://127.0.0.1:5210"))
    experiment = mlflow.set_experiment("boxing-app-inference")
    start = time.perf_counter()
    with mlflow.start_run(run_name="system2-synthetic-contract-probe", experiment_id=experiment.experiment_id,
                          tags={"record_kind": "synthetic_contract_probe", "model_sha256": manifest["model_sha256"],
                                "actual_billed_cost": "unknown"}) as run:
        with mlflow.start_span(name="system2_round_report_probe", span_type="CHAIN") as root:
            root.set_inputs({"source_kind": "synthetic_fixture", "attempt_ids": [a.attempt_id for a in ATTEMPTS]})
            with mlflow.start_span(name="evidence_gate", span_type="AGENT") as span:
                span.set_inputs({"attempts": evidence})
                span.set_outputs({"accepted_ids": [a.attempt_id for a in ATTEMPTS]})
            with mlflow.start_span(name="bonsai_27b_model_call", span_type="LLM") as span:
                span.set_inputs({"model": body["model"], "model_sha256": manifest["model_sha256"],
                                 "language": language, "fixture": evidence})
                request = urllib.request.Request(endpoint, data=json.dumps(body).encode(),
                                                 headers={"Content-Type": "application/json"})
                with urllib.request.urlopen(request, timeout=90) as response:
                    raw = json.load(response)
                span.set_outputs({"response": raw})
                span.set_attribute("observed_duration_ms", round((time.perf_counter() - start) * 1000, 1))
            proposal = ReportProposal.model_validate_json(raw["choices"][0]["message"]["content"])
            with mlflow.start_span(name="report_grounding_validation", span_type="AGENT") as span:
                validated = validate_proposal(proposal, ATTEMPTS, language)
                span.set_inputs({"proposal": proposal.model_dump(), "allowed_ids": [a.attempt_id for a in ATTEMPTS]})
                span.set_outputs({"status": validated["status"], "cited_ids": validated["evidence_attempt_ids"]})
            root.set_outputs({"status": validated["status"], "constraint_id": validated["next_constraint_id"]})
        mlflow.log_dict({"fixture_kind": "synthetic", "result": validated, "usage": raw.get("usage")},
                        "synthetic_report.json")
        mlflow.flush_trace_async_logging()
        trace_id = mlflow.get_last_active_trace_id()
        if not trace_id or not mlflow.get_trace(trace_id):
            raise RuntimeError("MLflow trace readback failed")
        validated.update(mlflow_run_id=run.info.run_id, mlflow_trace_id=trace_id,
                         model_usage=raw.get("usage"), source_kind="synthetic_fixture")
    return validated


if __name__ == "__main__":
    print(json.dumps(probe(os.getenv("BONSAI_URL", "http://127.0.0.1:15214/v1/chat/completions"),
                           os.getenv("REPORT_LANGUAGE", "en")), indent=2))
