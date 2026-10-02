"""Conservative coverage gate for an initiate/interact/terminate drill.

This consumes previously extracted Apple Vision frames for offline evaluation.
It does not recognize punches or certify a completed exchange.
"""
import hashlib
import json
from pathlib import Path

VERSION = "drill-coverage-v1"
REQUIRED = {
    "upper_body": ("leftShoulder", "rightShoulder", "leftWrist", "rightWrist"),
    "angle_exit": ("leftHip", "rightHip", "leftAnkle", "rightAnkle"),
}


def profile(frames: list[dict], clip_sha256: str, confidence: float = 0.55) -> dict:
    if not frames or not 0 < confidence <= 1:
        raise ValueError("Frames and confidence threshold are required")
    times = [frame["timeMs"] for frame in frames]
    if times != sorted(times) or any(time < 0 for time in times):
        raise ValueError("Frames must have ordered nonnegative timestamps")

    counts = {name: 0 for group in REQUIRED.values() for name in group}
    complete = {group: 0 for group in REQUIRED}
    longest_run = {group: 0 for group in REQUIRED}
    current_run = {group: 0 for group in REQUIRED}
    person = 0
    for frame in frames:
        people = frame.get("people", [])
        if people:
            person += 1
        # The extractor has no tracked identity. Multiple people are unusable.
        joints = people[0] if len(people) == 1 else {}
        visible = {name for name in counts if joints.get(name, {}).get("confidence", 0) >= confidence}
        for name in visible:
            counts[name] += 1
        for group, names in REQUIRED.items():
            if all(name in visible for name in names):
                complete[group] += 1
                current_run[group] += 1
                longest_run[group] = max(longest_run[group], current_run[group])
            else:
                current_run[group] = 0

    # Five consecutive usable samples at 10 fps are a provisional half-second gate.
    # Counts alone cannot establish temporal continuity or classify a movement.
    angle_observable = longest_run["angle_exit"] >= 5
    drill_observable = angle_observable and longest_run["upper_body"] >= 5
    result = {
        "schema_version": VERSION,
        "clip_sha256": clip_sha256,
        "extractor": "apple-vision-pose-offline",
        "frame_count": len(frames),
        "person_candidate_frames": person,
        "joint_visible_frames": counts,
        "complete_group_frames": complete,
        "longest_complete_run_frames": longest_run,
        "angle_exit_observable": angle_observable,
        "drill_coverage_sufficient": drill_observable,
        "engagement_classification": "not_attempted",
        "system1_route": "review_later" if drill_observable else "abstain_unobservable",
        "system2_route": "requires_human_labels" if drill_observable else "insufficient_visual_evidence",
        "laya_called": False,
        "bonsai_called": False,
        "interpretation": "Coverage only; no jab, combination, contact, angle exit, or drill success is inferred.",
    }
    return result


def profile_files(frames_path: Path, clip_path: Path) -> dict:
    with clip_path.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    return profile(json.loads(frames_path.read_text()), digest)
