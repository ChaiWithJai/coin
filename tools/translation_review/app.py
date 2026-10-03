"""Local, proposal-only French source review. No runtime export or promotion path."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
DECISIONS = {"pass", "fail", "defer"}


def load_source(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    if (not isinstance(data, dict) or data.get("purpose") != "translation_proposals_only"
            or data.get("runtimeEligible") is not False or not isinstance(data.get("items"), list)
            or not data["items"]):
        raise ValueError("Expected a nonempty proposal-only export with runtimeEligible=false")
    seen = set()
    for item in data["items"]:
        key = (item.get("blockID"), item.get("sourceItemID"))
        if (not all(isinstance(part, str) and part for part in key) or key in seen
                or not all(isinstance(item.get(field), str) for field in
                           ("sourceText", "sourceTextSHA256", "proposedFrench"))):
            raise ValueError("Invalid or duplicate source item")
        if hashlib.sha256(item["sourceText"].encode()).hexdigest() != item["sourceTextSHA256"]:
            raise ValueError("Source text hash mismatch")
        seen.add(key)
    return data


def item_key(item):
    return item["blockID"] + "::" + item["sourceItemID"]


def load_labels(path: Path, source):
    if not path.exists():
        return {"schemaVersion": 1, "purpose": "source_translation_review", "runtimeEligible": False,
                "jobID": source["jobID"], "sourceSHA256": source["sourceSHA256"], "labels": {}}
    labels = json.loads(path.read_text(encoding="utf-8"))
    if (labels.get("purpose") != "source_translation_review" or
            labels.get("jobID") != source["jobID"] or
            labels.get("sourceSHA256") != source["sourceSHA256"] or
            labels.get("runtimeEligible") is not False or not isinstance(labels.get("labels"), dict)):
        raise ValueError("Existing labels do not belong to this source export")
    return labels


def atomic_write(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".translation-labels-", suffix=".json", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_attempts(db_path, source):
    if not db_path or not db_path.exists():
        return {}
    result = {}
    try:
        with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as db:
            db.row_factory = sqlite3.Row
            rows = db.execute("""SELECT a.item_key, a.number, a.state, a.started, a.ended,
                    a.error, a.response, a.prompt_tokens, a.completion_tokens,
                    a.actual_cost_usd, a.estimated_cost_usd
                    FROM attempts a WHERE a.job_id=? ORDER BY a.item_key,a.number""", (source["jobID"],))
            for row in rows:
                entry = dict(row)
                result.setdefault(entry.pop("item_key"), []).append(entry)
    except (sqlite3.Error, OSError) as exc:
        raise ValueError(f"Cannot read attempt database: {exc}") from exc
    return result


def serve(source_path: Path, labels_path: Path, db_path: Path | None, host: str, port: int):
    source = load_source(source_path)
    labels = load_labels(labels_path, source)
    attempts = read_attempts(db_path, source)
    keys = {item_key(item): item for item in source["items"]}
    label_lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def send_json(self, code, value):
            payload = json.dumps(value, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self):
            route = urlparse(self.path).path
            if route == "/":
                payload = (HERE / "index.html").read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'none'; connect-src 'self'; base-uri 'none'; form-action 'none'")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            elif route == "/app.js":
                payload = (HERE / "app.js").read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "application/javascript; charset=utf-8")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            elif route == "/api/data":
                self.send_json(200, {"source": source, "labels": labels, "attempts": attempts,
                                     "labelsPath": str(labels_path)})
            else:
                self.send_json(404, {"error": "Not found"})

        def do_POST(self):
            if urlparse(self.path).path != "/api/label":
                return self.send_json(404, {"error": "Not found"})
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length < 1 or length > 20000:
                    raise ValueError("Invalid request size")
                body = json.loads(self.rfile.read(length))
                key = body.get("itemKey")
                decision = body.get("decision")
                notes = body.get("notes", "")
                if key not in keys or decision not in (*DECISIONS, None) or not isinstance(notes, str) or len(notes) > 10000:
                    raise ValueError("Invalid label")
                with label_lock:
                    if decision is None:
                        labels["labels"].pop(key, None)
                    else:
                        item = keys[key]
                        labels["labels"][key] = {"decision": decision, "notes": notes,
                            "sourceTextSHA256": item["sourceTextSHA256"],
                            "proposedFrenchSHA256": hashlib.sha256(item["proposedFrench"].encode()).hexdigest(),
                            "reviewKind": "local_reviewer_decision"}
                    atomic_write(labels_path, labels)
                    saved = labels["labels"].get(key)
                self.send_json(200, {"saved": True, "label": saved})
            except (ValueError, TypeError, json.JSONDecodeError) as exc:
                self.send_json(400, {"error": str(exc)})

        def log_message(self, format, *args):
            pass

    server = ThreadingHTTPServer((host, port), Handler)
    print(f"Review: http://{host}:{server.server_port}/", flush=True)
    print(f"Labels: {labels_path}", flush=True)
    server.serve_forever()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("proposal", type=Path, help="Any proposal-only JSON export")
    parser.add_argument("--labels", type=Path, help="Review file; defaults beside proposal")
    parser.add_argument("--db", type=Path, help="Optional batch SQLite file for model attempts")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5399)
    args = parser.parse_args()
    labels = args.labels or args.proposal.with_name(args.proposal.stem + "-review.json")
    db = args.db or args.proposal.with_name("batch.sqlite")
    serve(args.proposal, labels, db, args.host, args.port)


if __name__ == "__main__":
    main()
