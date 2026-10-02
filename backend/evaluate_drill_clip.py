"""Trace an offline drill visibility evaluation without promoting movement guesses."""
import argparse
import json
from pathlib import Path

import mlflow

from drill_evidence import profile_files

ROOT = Path(__file__).resolve().parents[3]


def evaluate(frames: Path, clip: Path, output: Path, tracking_uri: str) -> dict:
    mlflow.set_tracking_uri(tracking_uri)
    experiment = mlflow.set_experiment("boxing-app-inference")
    result = profile_files(frames, clip)
    result["frames_artifact"] = str(frames.relative_to(ROOT))
    result["media_retained_locally"] = True
    result["source_kind"] = "previously_extracted_personal_clip"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + "\n")
    with mlflow.start_run(run_name="drill-coverage-real-clip", experiment_id=experiment.experiment_id,
                          tags={"record_kind": "offline_drill_evaluation",
                                "clip_sha256": result["clip_sha256"],
                                "source_kind": result["source_kind"],
                                "actual_billed_cost": "unknown"}) as run:
        with mlflow.start_span(name="drill_evidence_evaluation", span_type="CHAIN") as root:
            root.set_inputs({"clip_sha256": result["clip_sha256"], "frame_count": result["frame_count"]})
            with mlflow.start_span(name="visual_processing_readback", span_type="TOOL") as span:
                span.set_inputs({"extractor": result["extractor"], "precomputed_frames": True})
                span.set_outputs({"person_candidate_frames": result["person_candidate_frames"],
                                  "joint_visible_frames": result["joint_visible_frames"],
                                  "longest_complete_run_frames": result["longest_complete_run_frames"]})
            with mlflow.start_span(name="system1_coverage_route", span_type="AGENT") as span:
                span.set_inputs({"protocol_id": "probe-combine-angle-v1",
                                 "drill_coverage_sufficient": result["drill_coverage_sufficient"]})
                span.set_outputs({"route": result["system1_route"], "laya_called": False})
            with mlflow.start_span(name="system2_report_gate", span_type="AGENT") as span:
                span.set_inputs({"accepted_attempt_ids": [], "visual_evidence": result["system1_route"]})
                span.set_outputs({"route": result["system2_route"], "bonsai_called": False})
            root.set_outputs({"system1_route": result["system1_route"],
                              "system2_route": result["system2_route"]})
        mlflow.log_dict(result, "drill_evidence.json")
        mlflow.flush_trace_async_logging()
        trace_id = mlflow.get_last_active_trace_id()
        if not trace_id or not mlflow.get_trace(trace_id):
            raise RuntimeError("MLflow trace readback failed")
        mlflow.set_tag("trace_id", trace_id)
        result["mlflow_run_id"] = run.info.run_id
        result["mlflow_trace_id"] = trace_id
    output.write_text(json.dumps(result, indent=2) + "\n")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", type=Path, default=ROOT / "work/posecli/frames.json")
    parser.add_argument("--clip", type=Path, default=ROOT / "work/fixtures/personal-bag-15s.mp4")
    parser.add_argument("--output", type=Path, default=ROOT / "outputs/coin/backend/drill-evidence-personal-bag-15s.json")
    parser.add_argument("--tracking-uri", default="http://127.0.0.1:5210")
    args = parser.parse_args()
    print(json.dumps(evaluate(args.frames, args.clip, args.output, args.tracking_uri), indent=2))
