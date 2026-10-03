#!/usr/bin/env python3
"""Compile completed activity review into lineage records, not a trained model.

The compiler is deliberately narrow: it accepts only labels bound to the exact
queue, requires structured corrections, and keeps every workout wholly in one
dataset split. Its outputs can be consumed by tools/verify_agentic_loop.py after
an independent training, evaluation, and deployment process creates the other
release artifacts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from app import atomic_write, item_key, load_labels, load_source

# This is the reviewed vocabulary shared by the source classifier and Coin's
# concrete runtime movement registry. A syntactically plausible new key must be
# registered and versioned before it can enter training data.
ACTIVITIES = {
    "shadowboxing", "boxing", "bag_work", "partner_work", "footwork",
    "strength", "conditioning", "mobility", "recovery", "unknown",
    "jumping_jacks", "burpees", "box_jumps", "squat_jumps", "squats",
    "lunges", "frontal_stance", "shoulder_circles", "hip_circles",
    "thoracic_rotations", "hamstring_sweeps", "pushups", "bench_press",
}


def stable_id(prefix: str, *parts: str) -> str:
    digest = hashlib.sha256("\0".join(parts).encode("utf-8")).hexdigest()[:24]
    return f"{prefix}-{digest}"


def parse_correction(notes: str, source_text: str) -> dict:
    try:
        value = json.loads(notes)
    except (TypeError, json.JSONDecodeError) as error:
        raise ValueError("fail decisions require JSON notes with activity and evidence_quote") from error
    if not isinstance(value, dict) or set(value) != {"activity", "evidence_quote"}:
        raise ValueError("correction must contain exactly activity and evidence_quote")
    activity, quote = value["activity"], value["evidence_quote"]
    if not isinstance(activity, str) or activity not in ACTIVITIES:
        raise ValueError("correction activity must be a registered movement key")
    if not isinstance(quote, str) or not quote.strip() or quote not in source_text:
        raise ValueError("correction evidence_quote must be an exact nonempty source-text excerpt")
    return {"activity": activity, "evidence_quote": quote}


def compile_review(source: dict, labels: dict, eval_workouts: set[str]) -> tuple[dict, dict, dict]:
    items = source["items"]
    known_workouts = {item["workout_id"] for item in items}
    unknown_eval = eval_workouts - known_workouts
    if unknown_eval:
        raise ValueError(f"eval workouts are absent from queue: {sorted(unknown_eval)}")
    train_workouts = known_workouts - eval_workouts
    if not eval_workouts or not train_workouts:
        raise ValueError("at least one whole workout is required in both train and eval splits")

    decisions, examples = [], []
    sessions: dict[str, list[dict]] = {}
    label_map = labels["labels"]
    expected_keys = {item_key(item) for item in items}
    unexpected_keys = set(label_map) - expected_keys
    if unexpected_keys:
        raise ValueError(f"labels contain items outside the exact queue: {sorted(unexpected_keys)}")
    for item in items:
        key = item_key(item)
        label = label_map.get(key)
        if not isinstance(label, dict):
            raise ValueError(f"unreviewed item: {key}")
        if label.get("sourceTextSHA256") != item["source_text_sha256"]:
            raise ValueError(f"source hash mismatch for label: {key}")
        if label.get("proposalActivity") != item["proposal_activity"]:
            raise ValueError(f"proposal mismatch for label: {key}")
        if label.get("reviewKind") != "local_reviewer_decision_not_promotion":
            raise ValueError(f"invalid review provenance: {key}")
        decision = label.get("decision")
        if decision == "defer":
            raise ValueError(f"deferred item cannot enter a dataset: {key}")
        if decision not in {"pass", "fail"}:
            raise ValueError(f"invalid review decision: {key}")

        session_id = f"source-workout:{item['workout_id']}"
        observation_id = stable_id("observation", source["job_id"], key,
                                   item["source_text_sha256"])
        review_id = stable_id("review", source["job_id"], key,
                              item["source_text_sha256"])
        observation = {
            "id": observation_id,
            "source_block_id": item["source_block_id"],
            "source_text_sha256": item["source_text_sha256"],
            "proposal_activity": item["proposal_activity"],
        }
        sessions.setdefault(session_id, []).append(observation)
        review = {
            "review_id": review_id,
            "session_id": session_id,
            "observation_id": observation_id,
            "state": "accepted" if decision == "pass" else "corrected",
            "queue_sha256": labels["queueSHA256"],
        }
        if decision == "fail":
            review["correction"] = parse_correction(label.get("notes", ""), item["source_text"])
        decisions.append(review)
        examples.append({
            "source_review_id": review_id,
            "session_id": session_id,
            "split": "eval" if item["workout_id"] in eval_workouts else "train",
        })

    record = {
        "schema_version": 1,
        "purpose": "reviewed_activity_observations",
        "source_job_id": source["job_id"],
        "queue_sha256": labels["queueSHA256"],
        "sessions": [
            {"session_id": session_id, "mode": "program", "observations": observations}
            for session_id, observations in sorted(sessions.items())
        ],
    }
    review = {"schema_version": 1, "purpose": "human_activity_review", "decisions": decisions}
    dataset = {
        "schema_version": 1,
        "purpose": "reviewed_examples_for_future_training_and_evaluation",
        "training_performed": False,
        "split_unit": "source_workout_session",
        "examples": examples,
    }
    return record, review, dataset


def compile_files(queue_path: Path, labels_path: Path, output_dir: Path,
                  eval_workouts: set[str]) -> dict:
    source = load_source(queue_path)
    labels = load_labels(labels_path, source)
    record, review, dataset = compile_review(source, labels, eval_workouts)
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = {"record.json": record, "review.json": review, "dataset.json": dataset}
    for name, value in outputs.items():
        atomic_write(output_dir / name, value)
    return {"output_dir": str(output_dir), "examples": len(dataset["examples"]),
            "train_sessions": sorted({e["session_id"] for e in dataset["examples"] if e["split"] == "train"}),
            "eval_sessions": sorted({e["session_id"] for e in dataset["examples"] if e["split"] == "eval"}),
            "training_performed": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("queue", type=Path)
    parser.add_argument("labels", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--eval-workout", action="append", required=True,
                        help="workout_id assigned wholly to eval; repeat for more")
    args = parser.parse_args()
    try:
        result = compile_files(args.queue, args.labels, args.output_dir, set(args.eval_workout))
    except ValueError as error:
        parser.error(str(error))
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
