"""Local review for unpromoted Coin activity proposals. No promotion endpoint exists here."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
DECISIONS = {"pass", "fail", "defer"}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def queue_sha256(source):
    return hashlib.sha256(canonical(source).encode()).hexdigest()


def load_source(path: Path):
    source = json.loads(path.read_text(encoding="utf-8"))
    if (not isinstance(source, dict) or source.get("schema_version") != 1
            or source.get("evidence_status") != "stored_model_proposals_for_review_not_labels"
            or not isinstance(source.get("items"), list) or not source["items"]
            or source.get("count") != len(source["items"])):
        raise ValueError("Expected a nonempty, unpromoted activity review queue")
    seen = set()
    for item in source["items"]:
        identity = (item.get("workout_id"), item.get("source_block_id"))
        if (not all(isinstance(value, str) and value for value in identity)
                or identity in seen or item.get("proposal_activity") != "unknown"
                or not isinstance(item.get("source_text"), str)
                or not isinstance(item.get("source_text_sha256"), str)):
            raise ValueError("Invalid or duplicate activity review item")
        seen.add(identity)
    return source


def item_key(item):
    return item["workout_id"] + "::" + item["source_block_id"]


def load_labels(path: Path, source):
    expected = {"schemaVersion": 1, "purpose": "activity_proposal_review",
                "runtimeEligible": False, "jobID": source["job_id"],
                "queueSHA256": queue_sha256(source), "labels": {}}
    if not path.exists():
        return expected
    labels = json.loads(path.read_text(encoding="utf-8"))
    if any(labels.get(key) != expected[key] for key in
           ("schemaVersion", "purpose", "runtimeEligible", "jobID", "queueSHA256")):
        raise ValueError("Existing labels do not belong to this exact review queue")
    if not isinstance(labels.get("labels"), dict):
        raise ValueError("Invalid label map")
    return labels


def atomic_write(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".activity-labels-", suffix=".json", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def serve(source_path: Path, labels_path: Path, host: str, port: int):
    source = load_source(source_path)
    labels = load_labels(labels_path, source)
    items = {item_key(item): item for item in source["items"]}
    lock = threading.Lock()

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
            if route == "/api/data":
                return self.send_json(200, {"source": source, "labels": labels,
                                            "labelsPath": str(labels_path)})
            files = {"/": ("index.html", "text/html; charset=utf-8"),
                     "/app.js": ("app.js", "application/javascript; charset=utf-8"),
                     "/style.css": ("style.css", "text/css; charset=utf-8")}
            if route not in files:
                return self.send_json(404, {"error": "Not found"})
            name, mime = files[route]
            payload = (HERE / name).read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'none'; connect-src 'self'; base-uri 'none'; form-action 'none'")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def do_POST(self):
            if urlparse(self.path).path != "/api/label":
                return self.send_json(404, {"error": "Not found"})
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 20000:
                    raise ValueError("Invalid request size")
                body = json.loads(self.rfile.read(length))
                key, decision, notes = body.get("itemKey"), body.get("decision"), body.get("notes", "")
                if key not in items or decision not in (*DECISIONS, None) or not isinstance(notes, str) or len(notes) > 10000:
                    raise ValueError("Invalid label")
                with lock:
                    if decision is None:
                        labels["labels"].pop(key, None)
                    else:
                        item = items[key]
                        labels["labels"][key] = {
                            "decision": decision, "notes": notes,
                            "sourceTextSHA256": item["source_text_sha256"],
                            "proposalActivity": item["proposal_activity"],
                            "reviewKind": "local_reviewer_decision_not_promotion",
                        }
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
    parser.add_argument("queue", type=Path)
    parser.add_argument("--labels", type=Path)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5400)
    args = parser.parse_args()
    labels = args.labels or args.queue.with_name(args.queue.stem + "-review.json")
    serve(args.queue, labels, args.host, args.port)


if __name__ == "__main__":
    main()
