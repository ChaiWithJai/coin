#!/usr/bin/env python3
"""Read-only freshness check for the bundled workout source catalog.

The verifier hashes the raw response bytes. It never rewrites the catalog or
normalizes HTML, because either operation could hide a source change that needs
human review before the workout prescription is updated.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit


SHA256 = re.compile(r"^[0-9a-f]{64}$")


def canonical_source_url(value: str) -> str:
    """Return the exact source URL with one trailing path slash and no fragment."""
    parts = urlsplit(value)
    if parts.scheme not in {"http", "https"} or not parts.netloc:
        raise ValueError("sourceURL must be an absolute HTTP(S) URL")
    path = parts.path.rstrip("/") + "/"
    return urlunsplit((parts.scheme, parts.netloc, path, parts.query, ""))


def fetch_raw(url: str, timeout: float) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "CoinSourceFreshness/1.0"},
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def verify_catalog(catalog_path: str | Path, fetch=fetch_raw, timeout: float = 15.0) -> dict:
    """Fetch every workout URL and compare raw bytes with its pinned digest."""
    path = Path(catalog_path)
    catalog = json.loads(path.read_text(encoding="utf-8"))
    workouts = catalog.get("workouts")
    if not isinstance(workouts, list):
        raise ValueError("catalog.workouts must be a list")

    matches = []
    missing = []
    drift = []
    fetch_failures = []
    seen_urls = set()
    for index, workout in enumerate(workouts):
        workout_id = workout.get("id") if isinstance(workout, dict) else None
        identity = workout_id if isinstance(workout_id, str) and workout_id else f"index:{index}"
        source_url = workout.get("sourceURL") if isinstance(workout, dict) else None
        expected = workout.get("sourceSHA256") if isinstance(workout, dict) else None
        missing_fields = []
        if not isinstance(source_url, str) or not source_url.strip():
            missing_fields.append("sourceURL")
        if not isinstance(expected, str) or not SHA256.fullmatch(expected):
            missing_fields.append("sourceSHA256")
        if missing_fields:
            missing.append({"workout_id": identity, "index": index, "fields": missing_fields})
            continue
        try:
            url = canonical_source_url(source_url)
        except ValueError as error:
            missing.append({"workout_id": identity, "index": index, "fields": ["sourceURL"], "error": str(error)})
            continue
        if url in seen_urls:
            missing.append({"workout_id": identity, "index": index, "fields": ["unique_sourceURL"], "url": url})
            continue
        seen_urls.add(url)
        try:
            raw = fetch(url, timeout)
            if not isinstance(raw, bytes):
                raise TypeError("fetcher must return bytes")
        except Exception as error:
            fetch_failures.append({"workout_id": identity, "url": url, "error": type(error).__name__})
            continue
        actual = hashlib.sha256(raw).hexdigest()
        result = {"workout_id": identity, "url": url, "expected_sha256": expected, "actual_sha256": actual}
        if actual == expected:
            matches.append(result)
        else:
            drift.append(result)

    return {
        "schema_version": 1,
        "check": "raw_html_sha256",
        "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "catalog_path": str(path),
        "catalog_version": catalog.get("catalogVersion"),
        "workout_count": len(workouts),
        "fetch_count": len(seen_urls),
        "matched_count": len(matches),
        "passed": not missing and not drift and not fetch_failures and len(matches) == len(workouts),
        "missing": missing,
        "drift": drift,
        "fetch_failures": fetch_failures,
        "matches": matches,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("catalog", nargs="?", default="ios/WorkoutCatalog.json")
    parser.add_argument("--timeout", type=float, default=15.0)
    args = parser.parse_args(argv)
    report = verify_catalog(args.catalog, timeout=args.timeout)
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
