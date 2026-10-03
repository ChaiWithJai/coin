#!/usr/bin/env python3
"""Compile explicitly approved activity reviews into a fail-closed Coin overlay.

This tool does not infer, review, or approve anything.  It requires three
independent, exact inputs: saved review decisions, a human release approval,
and a runtime-segment manifest exported from the same catalog build.  The iOS
loader performs the same catalog, source, wording, registry, and coverage
checks again before using the resulting file.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path

from app import canonical, item_key, load_labels, load_source, queue_sha256
from compile_dataset import ACTIVITIES, parse_correction

MOVEMENTS = ACTIVITIES - {"unknown", "partner_work", "footwork", "strength", "conditioning",
                          "mobility", "recovery"}
MOVEMENT_VERSION = "v1"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def decision_sha256(label: dict) -> str:
    """Bind release approval to the exact saved review decision."""
    return hashlib.sha256(canonical(label).encode()).hexdigest()


def _iso8601(value: object) -> str:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ValueError("reviewed_at must be an ISO-8601 UTC timestamp ending in Z")
    try:
        parsed = dt.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise ValueError("reviewed_at must be an ISO-8601 UTC timestamp") from error
    if parsed.tzinfo is None:
        raise ValueError("reviewed_at must include a timezone")
    return value


def _recipe(activity: str) -> dict:
    if activity in {"squats", "lunges"}:
        identifier, capability, validation = f"mediapipe-{activity[:-1]}-angle", "rep_candidate", "unvalidated"
    elif activity in {"boxing", "shadowboxing"}:
        identifier, capability, validation = "coin-exchange-tracker", "exchange_candidate", "unvalidated"
    else:
        identifier, capability, validation = "session-clock", "elapsed_only", "not_applicable"
    return {"id": identifier, "version": "v1", "capability": capability,
            "validationStatus": validation}


def _catalog_index(catalog: dict) -> dict:
    if catalog.get("schemaVersion") != 1 or not isinstance(catalog.get("workouts"), list):
        raise ValueError("invalid WorkoutCatalog")
    lessons = {}
    for lesson in catalog["workouts"]:
        blocks = {block["id"]: block for block in lesson.get("blocks", [])}
        if lesson.get("id") in lessons or len(blocks) != len(lesson.get("blocks", [])):
            raise ValueError("duplicate lesson or source block in WorkoutCatalog")
        lessons[lesson["id"]] = (lesson, blocks)
    return lessons


def compile_overlay(source: dict, labels: dict, approval: dict, manifest: dict,
                    catalog_data: bytes) -> dict:
    catalog = json.loads(catalog_data)
    catalog_hash = sha256_bytes(catalog_data)
    lessons = _catalog_index(catalog)
    if manifest.get("schema_version") != 1 or manifest.get("purpose") != "coin_runtime_segment_manifest":
        raise ValueError("invalid runtime segment manifest")
    lesson_id = manifest.get("lesson_id")
    if lesson_id not in lessons or manifest.get("catalog_sha256") != catalog_hash:
        raise ValueError("runtime manifest does not match the exact catalog")
    lesson, blocks = lessons[lesson_id]
    if manifest.get("source_sha256") != lesson.get("sourceSHA256"):
        raise ValueError("runtime manifest source hash mismatch")
    segments = manifest.get("segments")
    if (not isinstance(segments, list) or not segments
            or [s.get("runtime_segment_index") for s in segments] != list(range(len(segments)))):
        raise ValueError("runtime manifest must contain every segment once in index order")

    if (approval.get("schema_version") != 1
            or approval.get("purpose") != "runtime_drill_human_approval"
            or approval.get("queue_sha256") != queue_sha256(source)
            or approval.get("catalog_sha256") != catalog_hash
            or approval.get("lesson_id") != lesson_id):
        raise ValueError("release approval does not match the exact queue, catalog, and lesson")
    reviewer = approval.get("reviewer")
    if not isinstance(reviewer, str) or not reviewer.strip():
        raise ValueError("release approval requires a nonempty human reviewer")
    reviewed_at = _iso8601(approval.get("reviewed_at"))
    approvals = approval.get("approvals")
    if not isinstance(approvals, dict):
        raise ValueError("release approval requires an approvals map")

    queue = {item_key(item): item for item in source["items"] if item.get("workout_id") == lesson_id}
    proposals = []
    consumed = set()
    for segment in segments:
        block_id, source_item_id = segment.get("source_block_id"), segment.get("source_item_id")
        block = blocks.get(block_id)
        if block is None:
            raise ValueError(f"runtime segment references unknown source block: {block_id}")
        if source_item_id is not None:
            source_items = {item["id"]: item for item in block.get("sourceItems", [])}
            if source_item_id not in source_items:
                raise ValueError(f"runtime segment references unknown source item: {source_item_id}")
        key_values = [lesson_id, block_id] + ([source_item_id] if source_item_id else [])
        key = "::".join(key_values)
        item, label, signed = queue.get(key), labels["labels"].get(key), approvals.get(key)
        if not all(isinstance(value, dict) for value in (item, label, signed)):
            raise ValueError(f"segment lacks review and explicit approval: {key}")
        if (label.get("sourceTextSHA256") != item["source_text_sha256"]
                or label.get("proposalActivity") != item["proposal_activity"]
                or label.get("reviewKind") != "local_reviewer_decision_not_promotion"):
            raise ValueError(f"review decision lineage mismatch: {key}")
        if (signed.get("decision_sha256") != decision_sha256(label)
                or signed.get("proposal_approved") is not True
                or signed.get("measurement_approved") is not True):
            raise ValueError(f"segment lacks both exact human approvals: {key}")
        if label.get("decision") == "pass":
            activity = item["proposal_activity"]
        elif label.get("decision") == "fail":
            activity = parse_correction(label.get("notes", ""), item["source_text"])["activity"]
        else:
            raise ValueError(f"open or deferred review cannot be promoted: {key}")
        if activity not in MOVEMENTS:
            raise ValueError(f"activity is not a concrete registered runtime movement: {key}")
        consumed.add(key)
        index = segment["runtime_segment_index"]
        proposal_id = "runtime-" + hashlib.sha256(
            f"{catalog_hash}\0{lesson_id}\0{index}\0{activity}\0{decision_sha256(label)}".encode()
        ).hexdigest()[:24]
        review = {"state": "approved", "reviewer": reviewer, "reviewedAt": reviewed_at}
        proposals.append({
            "schemaVersion": 1, "proposalID": proposal_id, "catalogSHA256": catalog_hash,
            "sourceSHA256": lesson["sourceSHA256"],
            "target": {"kind": "runtime_segment", "lessonID": lesson_id,
                       "sourceBlockID": block_id, "sourceItemID": source_item_id,
                       "runtimeSegmentIndex": index},
            "sourceTitle": block["title"], "sourceInstructions": block["instructions"],
            "runtimeTitle": segment.get("runtime_title"),
            "runtimeInstructions": segment.get("runtime_instructions"),
            "movementKey": activity, "movementVersion": MOVEMENT_VERSION,
            "measurementRecipe": _recipe(activity), "review": review,
            "measurementReview": review,
        })
    if set(queue) != consumed:
        raise ValueError("lesson review queue and runtime manifest do not cover exactly the same targets")
    return {"schemaVersion": 1, "catalogSHA256": catalog_hash,
            "lessonID": lesson_id, "proposals": proposals}


def compile_files(queue_path: Path, labels_path: Path, approval_path: Path,
                  manifest_path: Path, catalog_path: Path, output_path: Path) -> dict:
    source = load_source(queue_path)
    labels = load_labels(labels_path, source)
    approval = json.loads(approval_path.read_text(encoding="utf-8"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    overlay = compile_overlay(source, labels, approval, manifest, catalog_path.read_bytes())
    output_path.parent.mkdir(parents=True, exist_ok=True)
    from app import atomic_write
    atomic_write(output_path, overlay)
    return {"output": str(output_path), "lesson_id": overlay["lessonID"],
            "proposals": len(overlay["proposals"]), "human_approved": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("queue", type=Path)
    parser.add_argument("labels", type=Path)
    parser.add_argument("approval", type=Path)
    parser.add_argument("runtime_manifest", type=Path)
    parser.add_argument("catalog", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        result = compile_files(args.queue, args.labels, args.approval, args.runtime_manifest,
                               args.catalog, args.output)
    except (ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
