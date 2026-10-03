#!/usr/bin/env python3
"""Verify one record -> review -> correct -> train -> evaluate -> deploy cycle.

The verifier does not train or deploy anything. It checks the release receipt that
joins those independently produced artifacts, including file digests, review
lineage, session-level split isolation, and evaluated/deployed artifact identity.
"""

import argparse
import hashlib
import json
from pathlib import Path


class VerificationError(ValueError):
    pass


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise VerificationError(f"cannot read {path}: {error}") from error


def required(data, key, context):
    value = data.get(key)
    if value is None or value == "" or value == []:
        raise VerificationError(f"{context}.{key} is required")
    return value


def resolved(base, value):
    path = Path(value)
    return path if path.is_absolute() else base / path


def verified_file(base, reference, context):
    path = resolved(base, required(reference, "path", context))
    expected = required(reference, "sha256", context)
    if not path.is_file():
        raise VerificationError(f"{context}.path does not exist: {path}")
    actual = digest(path)
    if actual != expected:
        raise VerificationError(f"{context}.sha256 mismatch: expected {expected}, got {actual}")
    return path, actual


def verify(manifest_path):
    manifest_path = Path(manifest_path).resolve()
    manifest = load(manifest_path)
    base = manifest_path.parent
    mode = required(manifest, "mode", "manifest")
    if mode not in {"program", "freestyle"}:
        raise VerificationError("manifest.mode must be program or freestyle")

    paths = {}
    hashes = {}
    for name in ("record", "review", "dataset", "model_artifact", "evaluation", "deployment"):
        reference = required(manifest, name, "manifest")
        paths[name], hashes[name] = verified_file(base, reference, f"manifest.{name}")

    record = load(paths["record"])
    review = load(paths["review"])
    dataset = load(paths["dataset"])
    evaluation = load(paths["evaluation"])
    deployment = load(paths["deployment"])

    sessions = required(record, "sessions", "record")
    observation_sessions = {}
    session_ids = set()
    for session in sessions:
        session_id = required(session, "session_id", "record.sessions[]")
        if session_id in session_ids:
            raise VerificationError(f"duplicate record session ID: {session_id}")
        session_ids.add(session_id)
        if required(session, "mode", "record.sessions[]") != mode:
            raise VerificationError(f"record session {session_id} mode does not match manifest.mode")
        for item in required(session, "observations", "record.sessions[]"):
            observation_id = required(item, "id", "record.sessions[].observations[]")
            if observation_id in observation_sessions:
                raise VerificationError("record observation IDs must be unique")
            observation_sessions[observation_id] = session_id

    decisions = required(review, "decisions", "review")
    decision_ids = []
    approved_review_ids = set()
    for decision in decisions:
        review_id = required(decision, "review_id", "review.decisions[]")
        observation_id = required(decision, "observation_id", "review.decisions[]")
        session_id = required(decision, "session_id", "review.decisions[]")
        state = required(decision, "state", "review.decisions[]")
        if state not in {"accepted", "corrected", "rejected"}:
            raise VerificationError(f"invalid review state for {review_id}: {state}")
        if observation_id not in observation_sessions:
            raise VerificationError(f"review {review_id} references unknown observation {observation_id}")
        if observation_sessions[observation_id] != session_id:
            raise VerificationError(f"review {review_id} has the wrong session for {observation_id}")
        if state == "corrected" and not decision.get("correction"):
            raise VerificationError(f"corrected review {review_id} has no correction")
        if state in {"accepted", "corrected"}:
            approved_review_ids.add(review_id)
        decision_ids.append(review_id)
    if len(decision_ids) != len(set(decision_ids)):
        raise VerificationError("review IDs must be unique")

    examples = required(dataset, "examples", "dataset")
    train_sessions = set()
    eval_sessions = set()
    used_reviews = set()
    review_sessions = {item["review_id"]: item["session_id"] for item in decisions}
    for example in examples:
        review_id = required(example, "source_review_id", "dataset.examples[]")
        if review_id not in approved_review_ids:
            raise VerificationError(f"dataset uses unapproved review {review_id}")
        if review_id in used_reviews:
            raise VerificationError(f"dataset repeats source review {review_id}")
        split = required(example, "split", "dataset.examples[]")
        example_session = required(example, "session_id", "dataset.examples[]")
        if review_sessions[review_id] != example_session:
            raise VerificationError(f"dataset session does not match source review {review_id}")
        if split == "train":
            train_sessions.add(example_session)
        elif split == "eval":
            eval_sessions.add(example_session)
        else:
            raise VerificationError(f"invalid dataset split: {split}")
        used_reviews.add(review_id)
    overlap = train_sessions & eval_sessions
    if overlap:
        raise VerificationError(f"sessions occur in both train and eval splits: {sorted(overlap)}")

    if required(evaluation, "artifact_sha256", "evaluation") != hashes["model_artifact"]:
        raise VerificationError("evaluation did not evaluate manifest.model_artifact")
    held_out = set(required(evaluation, "held_out_session_ids", "evaluation"))
    if not held_out or held_out != eval_sessions:
        raise VerificationError("evaluation held-out sessions must exactly match dataset eval sessions")
    if train_sessions & held_out:
        raise VerificationError("evaluation sessions leaked into training")
    if evaluation.get("passed") is not True:
        raise VerificationError("evaluation.passed must be true")

    if required(deployment, "mode", "deployment") != mode:
        raise VerificationError("deployment.mode does not match manifest.mode")
    if required(deployment, "artifact_sha256", "deployment") != hashes["model_artifact"]:
        raise VerificationError("deployment artifact was not the evaluated artifact")
    if required(deployment, "evaluation_sha256", "deployment") != hashes["evaluation"]:
        raise VerificationError("deployment does not reference the verified evaluation")

    return {
        "verified": True,
        "mode": mode,
        "record_session_ids": sorted(session_ids),
        "reviewed_decisions": len(decisions),
        "dataset_examples": len(examples),
        "train_sessions": sorted(train_sessions),
        "held_out_sessions": sorted(held_out),
        "artifact_sha256": hashes["model_artifact"],
        "deployment_sha256": hashes["deployment"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", help="JSON release receipt with paths and SHA-256 digests")
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.manifest), sort_keys=True, indent=2))
    except VerificationError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
