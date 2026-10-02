"""Audit the iOS full-body framing gate on existing 10 fps pose files.

Only aggregate counts and file hashes enter MLflow. Pose arrays and video stay local.
These clips check framing behavior; they are not boxing-phase ground truth.
"""
import argparse
import hashlib
import json
from pathlib import Path

REQUIRED_JOINTS = (11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28)
GATES = {
    "full_body": REQUIRED_JOINTS,
    "upper_body": (11, 12, 13, 14, 15, 16, 23, 24),
    "lower_body": (23, 24, 25, 26, 27, 28),
}
MIN_VISIBILITY = 0.55
SUSTAIN_SECONDS = 0.5


def frame_ready(frame, required_joints=REQUIRED_JOINTS):
    poses = frame.get("poses") or []
    if not poses:
        return False
    joints = poses[0].get("landmarks") or []  # iOS uses numPoses=1.
    return len(joints) > max(required_joints) and all(
        joints[i].get("visibility", 0) >= MIN_VISIBILITY
        and 0 <= joints[i].get("x", -1) <= 1
        and 0 <= joints[i].get("y", -1) <= 1
        for i in required_joints
    )


def evaluate(path, case_id):
    frames = json.loads(path.read_text())
    counts = {}
    for gate_name, joints in GATES.items():
        began_at = None
        candidates = sustained = 0
        for frame in frames:
            timestamp = float(frame["clip_seconds"])
            ready = frame_ready(frame, joints)
            if ready:
                candidates += 1
                if began_at is None:
                    began_at = timestamp
                if timestamp - began_at >= SUSTAIN_SECONDS:
                    sustained += 1
            else:
                began_at = None
        counts[gate_name] = {"candidate_frames": candidates, "sustained_ready_frames": sustained}
    return {
        "case_id": case_id,
        "pose_file_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "frame_count": len(frames),
        "candidate_frames": counts["full_body"]["candidate_frames"],
        "sustained_ready_frames": counts["full_body"]["sustained_ready_frames"],
        "visibility_gates": counts,
        "required_joints": list(REQUIRED_JOINTS),
        "minimum_visibility": MIN_VISIBILITY,
        "sustain_seconds": SUSTAIN_SECONDS,
        "interpretation": "framing gate only; no punch, exchange, or drill labels",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", action="append", required=True, help="case_id:path/to/poses.json")
    parser.add_argument("--mlflow", action="store_true")
    args = parser.parse_args()
    results = []
    for value in args.case:
        case_id, path = value.split(":", 1)
        results.append(evaluate(Path(path), case_id))
    report = {"version": "framing-gate-v1", "results": results,
              "actual_billed_cost_usd": None, "cost_status": "Local processing only; hardware and electricity cost unmeasured"}
    if args.mlflow:
        import mlflow
        mlflow.set_tracking_uri("http://127.0.0.1:5210")
        experiment = mlflow.set_experiment("boxing-app-inference")
        with mlflow.start_run(experiment_id=experiment.experiment_id, run_name="framing-gate-negative-control",
                              tags={"evidence_type": "existing_pose_file_framing_audit", "model_calls": "none",
                                    "human_exchange_labels": "none", "cost_status": "local_hardware_unmeasured"}) as run:
            for result in results:
                with mlflow.start_span(name="pose_framing_gate", span_type="TOOL") as span:
                    span.set_inputs({"case_id": result["case_id"], "frame_count": result["frame_count"],
                                     "minimum_visibility": MIN_VISIBILITY, "sustain_seconds": SUSTAIN_SECONDS})
                    span.set_outputs({"candidate_frames": result["candidate_frames"],
                                      "sustained_ready_frames": result["sustained_ready_frames"],
                                      "visibility_gates": result["visibility_gates"]})
                mlflow.log_metric(f"{result['case_id']}_candidate_frames", result["candidate_frames"])
                mlflow.log_metric(f"{result['case_id']}_sustained_ready_frames", result["sustained_ready_frames"])
            mlflow.log_dict(report, "framing-gate-report.json")
            mlflow.flush_trace_async_logging()
            report["mlflow_run_id"] = run.info.run_id
        trace_id = mlflow.get_last_active_trace_id()
        if not trace_id or not mlflow.get_trace(trace_id):
            raise RuntimeError("MLflow trace readback failed")
        report["mlflow_trace_id"] = trace_id
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
