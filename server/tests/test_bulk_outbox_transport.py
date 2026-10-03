import io
import json
import sqlite3
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

from telemetry import Outbox


class BulkOutboxTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "events.sqlite3"

    def test_claim_many_leases_a_bounded_ordered_batch(self):
        box = Outbox(self.path)
        event_ids = [box.enqueue({"sequence": index}) for index in range(4)]
        claimed = box.claim_many(3, now=10, lease_seconds=5)
        self.assertEqual([event["event_id"] for event in claimed], event_ids[:3])
        self.assertEqual([event["payload"]["sequence"] for event in claimed], [0, 1, 2])
        self.assertEqual({event["owner"] for event in claimed}, {claimed[0]["owner"]})
        self.assertTrue(all(event["attempts"] == 1 for event in claimed))
        remaining = box.claim_many(3, now=11)
        self.assertEqual([event["event_id"] for event in remaining], event_ids[3:])

    def test_bulk_lease_remains_owned_until_requested_deadline(self):
        box = Outbox(self.path)
        event_id = box.enqueue({"sequence": 1})
        original = box.claim_many(1, now=10, lease_seconds=1005)[0]
        self.assertIsNone(box.claim(now=1014))
        replay = box.claim(now=1015)
        self.assertEqual(replay["event_id"], event_id)
        self.assertEqual(replay["attempts"], 2)
        self.assertNotEqual(replay["owner"], original["owner"])

    def test_finish_many_preserves_retry_error_and_stale_sibling(self):
        box = Outbox(self.path)
        for sequence in range(3):
            box.enqueue({"sequence": sequence})
        first, second, third = box.claim_many(3, now=10)
        stale_first = dict(first, owner="not-the-owner")
        outcomes = box.finish_many(
            [
                {"event": stale_first, "success": True},
                {"event": second, "success": False, "error": "SinkTimeout"},
                {"event": third, "success": True},
            ],
            now=20,
        )
        self.assertEqual([outcome["finished"] for outcome in outcomes], [False, True, True])
        self.assertEqual(outcomes[0]["error"], "Lease no longer owned")
        self.assertEqual(outcomes[1]["error"], "SinkTimeout")
        self.assertEqual(box.counts(), {"delivered": 1, "leased": 1, "pending": 1})
        with sqlite3.connect(box.path) as db:
            retry = db.execute("SELECT available,last_error FROM events WHERE id=?", (second["event_id"],)).fetchone()
        self.assertEqual(retry, (22, "SinkTimeout"))

    def test_claim_many_rejects_unbounded_or_invalid_limits(self):
        box = Outbox(self.path)
        for limit in (0, -1, True, 1001, "20"):
            with self.subTest(limit=limit), self.assertRaises(ValueError):
                box.claim_many(limit)


class MacDrainTests(unittest.TestCase):
    def events(self):
        return [{"event_id": f"event-{index}", "payload": {"sequence": index}, "owner": "owner", "attempts": 1} for index in range(3)]

    def test_drain_uses_bulk_calls_and_duration_derived_from_limit(self):
        from backend import pull_telemetry
        events = self.events()
        calls = []
        delivered = []

        def fake_remote(action, payload=None):
            calls.append((action, payload))
            if action == "claim-many": return events
            if action == "finish-many": return [{"event_id": result["event"]["event_id"], "finished": True, "success": result["success"]} for result in payload["results"]]
            if action == "counts": return {"delivered": 3}
            raise AssertionError(action)

        sink_module = types.ModuleType("mlflow_sink")
        sink_module.MLflowSink = lambda: lambda event_id, payload: delivered.append((event_id, payload))
        with patch.dict(sys.modules, {"mlflow_sink": sink_module}), patch.object(pull_telemetry, "remote", fake_remote):
            output = io.StringIO()
            with redirect_stdout(output): pull_telemetry.drain(limit=201)
        self.assertEqual([action for action, _ in calls], ["claim-many", "finish-many", "counts"])
        self.assertEqual(calls[0][1], {"limit": 201, "lease_seconds": 1005})
        self.assertEqual([event_id for event_id, _ in delivered], ["event-0", "event-1", "event-2"])
        self.assertEqual(json.loads(output.getvalue())["delivered_this_pass"], 3)

    def test_drain_finishes_each_result_before_reporting_sink_failure(self):
        from backend import pull_telemetry
        events = self.events()
        finished = []

        def fake_remote(action, payload=None):
            if action == "claim-many": return events
            if action == "finish-many":
                finished.extend(payload["results"])
                return [{"event_id": result["event"]["event_id"], "finished": True, "success": result["success"]} for result in payload["results"]]
            if action == "counts": return {"delivered": 2, "pending": 1}
            raise AssertionError(action)

        def sink(event_id, payload):
            if event_id == "event-1": raise TimeoutError("fixture")

        sink_module = types.ModuleType("mlflow_sink")
        sink_module.MLflowSink = lambda: sink
        with patch.dict(sys.modules, {"mlflow_sink": sink_module}), patch.object(pull_telemetry, "remote", fake_remote):
            with redirect_stdout(io.StringIO()), self.assertRaisesRegex(RuntimeError, "1 telemetry event"):
                pull_telemetry.drain(limit=3)
        self.assertEqual([result["success"] for result in finished], [True, False, True])
        self.assertEqual(finished[1]["error"], "TimeoutError")


if __name__ == "__main__":
    unittest.main()
