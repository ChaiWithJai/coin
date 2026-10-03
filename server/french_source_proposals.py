"""Unreviewed French wording proposals for a deliberately small source sample.

This module never changes the bundled catalog or feeds the workout runtime.
Run it to produce a review artifact; a human must approve wording separately.
"""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[1] / "ios" / "WorkoutCatalog.json"
OUTPUT = Path(__file__).resolve().parent / "proposals" / "basic-w1-d1-fr-unreviewed.json"
EXPECTED_LESSON_SHA256 = "25b017c54422132ce7308dfa9abf66e660d2f699f68d7afcc6a660c4e4e066cb"

# Exact source-item identifiers and wording are intentional. A changed snapshot
# fails closed instead of attaching an old proposal to new source material.
PROPOSALS = {
    ("basic-w1-d1-p3-s2-1", "p3-b2"): ("DYNAMIC WARM-UP:", "ÉCHAUFFEMENT DYNAMIQUE :"),
    ("basic-w1-d1-p3-s3-1", "p3-b4"): ("FR0NTAL STANCE DRILL", "EXERCICE DE GARDE DE FACE"),
    ("basic-w1-d1-p3-s3-1", "p3-b5"): (
        "4 ROUNDS OF 2 MINUTES WITH 30 SECONDS OF REST IN BETWEEN.",
        "4 rounds de 2 minutes avec 30 secondes de repos entre les rounds.",
    ),
}


def numbers(text: str) -> list[str]:
    return re.findall(r"(?<![\w])\d+(?![\w])", text)


def build(catalog: dict) -> dict:
    lesson = next(day for day in catalog["workouts"] if day["id"] == "basic-w1-d1")
    if lesson["sourceSHA256"] != EXPECTED_LESSON_SHA256:
        raise ValueError("Source snapshot hash changed")
    found = {}
    for block in lesson["blocks"]:
        for item in block["sourceItems"]:
            key = (block["id"], item["id"])
            if key not in PROPOSALS:
                continue
            expected, french = PROPOSALS[key]
            if item["text"] != expected:
                raise ValueError(f"Source wording changed: {key}")
            if numbers(expected) != numbers(french):
                raise ValueError(f"Numeric mismatch: {key}")
            if key in found:
                raise ValueError(f"Duplicate source item: {key}")
            found[key] = {
                "blockID": block["id"],
                "sourceItemID": item["id"],
                "sourceText": expected,
                "sourceTextSHA256": hashlib.sha256(expected.encode()).hexdigest(),
                "proposedFrench": french,
                "sourceDemoURLs": item["demoURLs"],
                "prescription": {
                    key: block[key]
                    for key in ("completion", "rounds", "durationSeconds", "restSeconds", "sets", "reps")
                },
                "reviewStatus": "unreviewed",
            }
    if set(found) != set(PROPOSALS):
        raise ValueError(f"Missing source items: {set(PROPOSALS) - set(found)}")
    return {
        "schemaVersion": 1,
        "purpose": "translation_proposals_only",
        "runtimeEligible": False,
        "lessonID": lesson["id"],
        "sourceURL": lesson["sourceURL"],
        "sourceSHA256": lesson["sourceSHA256"],
        "items": [found[key] for key in PROPOSALS],
    }


if __name__ == "__main__":
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(build(json.loads(CATALOG.read_text())), ensure_ascii=False, indent=2) + "\n")
    print(OUTPUT)
