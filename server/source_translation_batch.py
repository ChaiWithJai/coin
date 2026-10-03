"""Durable, proposal-only French translation of exact workout source items.

This is an offline worker. Its outputs are never imported into the app runtime.
Inference is at least once after a crash; cache keys include immutable source,
prompt, and model identities. Callers must schedule it behind live inference.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import time
import urllib.request
from contextlib import contextmanager
from pathlib import Path

SCHEMA_VERSION = 1
PROMPT_VERSION = "source-fr-proposal-v1"
PROMPT = (
    "Translate this exact boxing workout source item into natural French. "
    "Preserve every number, exercise prescription, and named exercise. "
    "Do not invent coaching advice or infer a performed movement. "
    "Return only JSON with keys proposedFrench (string) and ambiguityFlags "
    "(array of short strings). Flag unclear text, technique, or typography."
)
NUMBERS = re.compile(r"(?<![\w])\d+(?:[.,]\d+)?(?![\w])")


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def sha(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def source_items(catalog, lesson_id):
    """Return complete ordered day manifest or fail on ambiguous source identity."""
    if not isinstance(catalog, dict) or not isinstance(catalog.get("workouts"), list):
        raise ValueError("Invalid catalog")
    days = [day for day in catalog["workouts"] if day.get("id") == lesson_id]
    if len(days) != 1:
        raise ValueError("Expected exactly one lesson")
    day = days[0]
    source_sha = day.get("sourceSHA256")
    if not isinstance(source_sha, str) or not re.fullmatch(r"[0-9a-f]{64}", source_sha):
        raise ValueError("Missing exact source snapshot SHA")
    manifest, ids = [], set()
    for block in day.get("blocks", []):
        block_id = block.get("id")
        if not isinstance(block_id, str) or not block_id:
            raise ValueError("Missing block ID")
        for item in block.get("sourceItems", []):
            item_id, text = item.get("id"), item.get("text")
            key = item_id
            if (not isinstance(item_id, str) or not item_id or key in ids or
                    not isinstance(text, str) or not text.strip() or len(text) > 4000):
                raise ValueError("Invalid, duplicate, or oversized source item")
            ids.add(key)
            demos = item.get("demoURLs", [])
            if not isinstance(demos, list) or any(not isinstance(url, str) for url in demos):
                raise ValueError("Invalid source demo links")
            manifest.append({
                "lessonID": lesson_id, "sourceSHA256": source_sha,
                "blockID": block_id, "sourceItemID": item_id,
                "sourceText": text, "sourceTextSHA256": sha(text),
                "sourceDemoURLs": demos, "sourceURL": block.get("sourceURL", day.get("sourceURL")),
                "prescription": {key: block.get(key) for key in
                                 ("completion", "rounds", "durationSeconds", "restSeconds", "sets", "reps")},
            })
    exclusions = day.get("sourceExclusions", [])
    if not isinstance(exclusions, list):
        raise ValueError("Invalid source exclusions")
    exclusion_ids = [item.get("id") for item in exclusions]
    if (not manifest or any(not isinstance(item_id, str) or not item_id for item_id in exclusion_ids)
            or len(exclusion_ids) != len(set(exclusion_ids)) or ids.intersection(exclusion_ids)
            or day.get("sourceItemCount") != len(manifest) + len(exclusions)):
        raise ValueError("Source item coverage differs from catalog count")
    return manifest


def validate_proposal(item, response):
    if not isinstance(response, dict) or set(response) != {"proposedFrench", "ambiguityFlags"}:
        raise ValueError("Model response must contain only French and ambiguity flags")
    french, flags = response["proposedFrench"], response["ambiguityFlags"]
    if not isinstance(french, str) or not french.strip() or len(french) > 5000:
        raise ValueError("Invalid French proposal")
    if not isinstance(flags, list) or len(flags) > 20 or any(
            not isinstance(flag, str) or not flag.strip() or len(flag) > 200 for flag in flags):
        raise ValueError("Invalid ambiguity flags")
    if NUMBERS.findall(item["sourceText"]) != NUMBERS.findall(french):
        raise ValueError("Numeric prescription mismatch")
    return {"proposedFrench": french.strip(), "ambiguityFlags": flags}


class Store:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.db() as db:
            db.executescript("""
              PRAGMA journal_mode=WAL;
              CREATE TABLE IF NOT EXISTS jobs (
                id TEXT PRIMARY KEY, manifest TEXT NOT NULL, state TEXT NOT NULL,
                created REAL NOT NULL, prompt_version TEXT NOT NULL, model_identity TEXT NOT NULL);
              CREATE TABLE IF NOT EXISTS items (
                job_id TEXT NOT NULL, ordinal INTEGER NOT NULL, item_key TEXT NOT NULL,
                source TEXT NOT NULL, cache_key TEXT NOT NULL, state TEXT NOT NULL,
                lease_until REAL, attempts INTEGER NOT NULL DEFAULT 0, proposal TEXT, error TEXT,
                PRIMARY KEY(job_id, item_key));
              CREATE TABLE IF NOT EXISTS attempts (
                job_id TEXT NOT NULL, item_key TEXT NOT NULL, number INTEGER NOT NULL,
                state TEXT NOT NULL, started REAL NOT NULL, ended REAL,
                error TEXT, response TEXT, prompt_tokens INTEGER, completion_tokens INTEGER,
                actual_cost_usd REAL, estimated_cost_usd REAL,
                PRIMARY KEY(job_id, item_key, number));
              CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, proposal TEXT NOT NULL);
            """)

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA synchronous=FULL")
        try:
            with db:
                yield db
        finally:
            db.close()

    def submit_day(self, catalog, lesson_id, model_identity, prompt_version=PROMPT_VERSION):
        if not isinstance(model_identity, str) or not model_identity.strip():
            raise ValueError("Pinned model identity required")
        manifest = source_items(catalog, lesson_id)
        envelope = {"manifest": manifest, "model": model_identity, "prompt": prompt_version}
        job_id = sha(canonical(envelope))
        with self.db() as db:
            existing = db.execute("SELECT manifest FROM jobs WHERE id=?", (job_id,)).fetchone()
            if existing:
                if existing["manifest"] != canonical(manifest):
                    raise ValueError("Job ID collision")
                return job_id
            db.execute("INSERT INTO jobs VALUES (?,?,?,?,?,?)", (
                job_id, canonical(manifest), "pending", time.time(), prompt_version, model_identity))
            for ordinal, item in enumerate(manifest):
                key = canonical([item["blockID"], item["sourceItemID"]])
                cache_key = sha(canonical({"source": item, "prompt": prompt_version, "model": model_identity}))
                db.execute("INSERT INTO items (job_id,ordinal,item_key,source,cache_key,state) VALUES (?,?,?,?,?,?)",
                           (job_id, ordinal, key, canonical(item), cache_key, "pending"))
        return job_id

    def claim(self, job_id, lease_seconds=180, max_attempts=3):
        now = time.time()
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("""SELECT * FROM items WHERE job_id=? AND attempts<? AND
                (state='pending' OR (state='running' AND lease_until<?))
                ORDER BY ordinal LIMIT 1""", (job_id, max_attempts, now)).fetchone()
            if row is None:
                return None
            cached = db.execute("SELECT proposal FROM cache WHERE key=?", (row["cache_key"],)).fetchone()
            if cached:
                db.execute("UPDATE items SET state='done',proposal=?,error=NULL WHERE job_id=? AND item_key=?",
                           (cached["proposal"], job_id, row["item_key"]))
                return {"cached": True, "item": json.loads(row["source"])}
            number = row["attempts"] + 1
            db.execute("UPDATE items SET state='running',attempts=?,lease_until=?,error=NULL WHERE job_id=? AND item_key=?",
                       (number, now + lease_seconds, job_id, row["item_key"]))
            db.execute("INSERT INTO attempts (job_id,item_key,number,state,started) VALUES (?,?,?,?,?)",
                       (job_id, row["item_key"], number, "running", now))
            return {"cached": False, "item": json.loads(row["source"]), "item_key": row["item_key"],
                    "number": number, "cache_key": row["cache_key"]}

    def finish(self, job_id, claim, response=None, error=None, usage=None):
        if claim.get("cached"):
            return
        item = claim["item"]
        try:
            proposal = validate_proposal(item, response) if error is None else None
        except (ValueError, TypeError) as exc:
            proposal, error = None, str(exc)
        usage = usage or {}
        # Provider token counts may be known; USD stays unknown until billed data exists.
        tokens = (usage.get("prompt_tokens"), usage.get("completion_tokens"))
        with self.db() as db:
            row = db.execute("SELECT state,attempts FROM items WHERE job_id=? AND item_key=?",
                             (job_id, claim["item_key"])).fetchone()
            if not row or row["state"] != "running" or row["attempts"] != claim["number"]:
                raise ValueError("Stale claim")
            db.execute("""UPDATE attempts SET state=?,ended=?,error=?,response=?,
                prompt_tokens=?,completion_tokens=?,actual_cost_usd=NULL,estimated_cost_usd=NULL
                WHERE job_id=? AND item_key=? AND number=?""",
                ("failed" if error else "done", time.time(), error,
                 canonical(response) if response is not None else None, *tokens,
                 job_id, claim["item_key"], claim["number"]))
            if error:
                db.execute("UPDATE items SET state='pending',lease_until=NULL,error=? WHERE job_id=? AND item_key=?",
                           (str(error), job_id, claim["item_key"]))
            else:
                body = canonical(proposal)
                db.execute("INSERT OR REPLACE INTO cache VALUES (?,?)", (claim["cache_key"], body))
                db.execute("UPDATE items SET state='done',lease_until=NULL,proposal=?,error=NULL WHERE job_id=? AND item_key=?",
                           (body, job_id, claim["item_key"]))

    def export_day(self, job_id):
        with self.db() as db:
            job = db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
            if job is None:
                raise ValueError("Unknown job")
            rows = db.execute("SELECT * FROM items WHERE job_id=? ORDER BY ordinal", (job_id,)).fetchall()
            manifest = json.loads(job["manifest"])
            if len(rows) != len(manifest) or any(row["state"] != "done" for row in rows):
                raise ValueError("Whole-day coverage incomplete")
            items = []
            for source, row in zip(manifest, rows):
                if canonical(source) != row["source"]:
                    raise ValueError("Source drift")
                items.append({**source, **json.loads(row["proposal"]), "reviewStatus": "unreviewed"})
            return {"schemaVersion": SCHEMA_VERSION, "purpose": "translation_proposals_only",
                    "runtimeEligible": False, "lessonID": manifest[0]["lessonID"],
                    "sourceSHA256": manifest[0]["sourceSHA256"], "jobID": job_id,
                    "promptVersion": job["prompt_version"], "modelIdentity": job["model_identity"],
                    "actualCostUSD": None, "estimatedCostUSD": None, "items": items}

    def status(self, job_id):
        with self.db() as db:
            job = db.execute("SELECT id,model_identity,prompt_version FROM jobs WHERE id=?", (job_id,)).fetchone()
            if job is None:
                raise ValueError("Unknown job")
            rows = db.execute("SELECT state,COUNT(*) AS n FROM items WHERE job_id=? GROUP BY state", (job_id,)).fetchall()
            attempts = db.execute("SELECT COUNT(*) FROM attempts WHERE job_id=?", (job_id,)).fetchone()[0]
            return {"jobID": job_id, "modelIdentity": job["model_identity"],
                    "promptVersion": job["prompt_version"],
                    "counts": {row["state"]: row["n"] for row in rows}, "attempts": attempts,
                    "actualCostUSD": None, "estimatedCostUSD": None}


def process_one(store, job_id, model_client, *, lease_seconds=180):
    claim = store.claim(job_id, lease_seconds=lease_seconds)
    if claim is None:
        return None
    if claim["cached"]:
        return {"state": "cached", "item": claim["item"]}
    try:
        response, usage = model_client.propose(claim["item"])
        store.finish(job_id, claim, response=response, usage=usage)
        return {"state": "done", "item": claim["item"], "usage": usage}
    except Exception as exc:
        store.finish(job_id, claim, error=str(exc))
        return {"state": "failed", "item": claim["item"], "error": str(exc)}


class ModelClient:
    """Minimal local OpenAI-compatible chat client; caller controls GPU scheduling."""

    def __init__(self, endpoint, model, timeout=60):
        self.endpoint, self.model, self.timeout = endpoint, model, timeout

    def propose(self, item):
        body = {"model": self.model, "temperature": 0, "max_tokens": 300,
                "messages": [{"role": "system", "content": PROMPT},
                             {"role": "user", "content": canonical(item)}]}
        request = urllib.request.Request(self.endpoint, data=canonical(body).encode(),
                                         headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=self.timeout) as response:
            result = json.load(response)
        content = result["choices"][0]["message"]["content"]
        return json.loads(content), result.get("usage", {})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    submit = commands.add_parser("submit-day")
    submit.add_argument("--catalog", required=True)
    submit.add_argument("--lesson", required=True)
    submit.add_argument("--model-identity", required=True)
    for name in ("status", "export", "one"):
        sub = commands.add_parser(name)
        sub.add_argument("--job", required=True)
        if name == "one":
            sub.add_argument("--endpoint", required=True)
            sub.add_argument("--model", required=True)
    args = parser.parse_args()
    store = Store(args.db)
    if args.command == "submit-day":
        result = {"jobID": store.submit_day(json.loads(Path(args.catalog).read_text()),
                                             args.lesson, args.model_identity)}
    elif args.command == "status":
        result = store.status(args.job)
    elif args.command == "export":
        result = store.export_day(args.job)
    else:
        result = process_one(store, args.job, ModelClient(args.endpoint, args.model))
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
