import types
import unittest
import uuid
import sys
from unittest.mock import Mock, patch

try:
    import mlflow  # noqa: F401
except ModuleNotFoundError:
    mlflow_stub = types.ModuleType("mlflow")
    mlflow_stub.MlflowClient = object
    sys.modules["mlflow"] = mlflow_stub

from backend.mlflow_sink import MLflowSink


class BatchSinkTests(unittest.TestCase):
    def sink(self):
        sink = MLflowSink.__new__(MLflowSink)
        sink.experiment = types.SimpleNamespace(experiment_id="40")
        sink.client = Mock()
        return sink

    def test_flushes_once_then_verifies_each_created_run_and_trace(self):
        sink = self.sink()
        ids = [str(uuid.uuid4()) for _ in range(3)]
        sink._finished_run = Mock(return_value=None)
        sink._create = Mock(side_effect=[("run-0", "trace-0"), ("run-1", "trace-1"), ("run-2", "trace-2")])

        def run_readback(run_id):
            index = run_id[-1]
            return types.SimpleNamespace(
                info=types.SimpleNamespace(status="FINISHED"),
                data=types.SimpleNamespace(tags={"event_id": ids[int(index)]}),
            )

        sink.client.get_run.side_effect = run_readback
        events = [{"event_id": event_id, "payload": {}} for event_id in ids]
        with patch("backend.mlflow_sink.mlflow.flush_trace_async_logging", create=True) as flush, patch(
            "backend.mlflow_sink.mlflow.get_trace", create=True, side_effect=[object(), None, object()]
        ) as get_trace:
            results = sink.deliver_many(events)

        flush.assert_called_once_with()
        self.assertEqual(get_trace.call_count, 3)
        self.assertEqual([result["success"] for result in results], [True, False, True])
        self.assertEqual(results[1]["error"], "RuntimeError")

    def test_dedup_requires_a_finished_run_with_durable_trace(self):
        sink = self.sink()
        incomplete = types.SimpleNamespace(data=types.SimpleNamespace(tags={"trace_id": "missing"}))
        complete = types.SimpleNamespace(data=types.SimpleNamespace(tags={"trace_id": "durable"}))
        sink.client.search_runs.return_value = [incomplete, complete]
        with patch("backend.mlflow_sink.mlflow.get_trace", create=True, side_effect=[None, object()]) as get_trace:
            result = sink._finished_run(str(uuid.uuid4()))
        self.assertIs(result, complete)
        self.assertEqual(get_trace.call_count, 2)

    def test_creation_failure_does_not_fail_successful_siblings(self):
        sink = self.sink()
        ids = [str(uuid.uuid4()) for _ in range(2)]
        sink._finished_run = Mock(return_value=None)
        sink._create = Mock(side_effect=[ValueError("bad payload"), ("run-1", "trace-1")])
        sink.client.get_run.return_value = types.SimpleNamespace(
            info=types.SimpleNamespace(status="FINISHED"),
            data=types.SimpleNamespace(tags={"event_id": ids[1]}),
        )
        with patch("backend.mlflow_sink.mlflow.flush_trace_async_logging", create=True) as flush, patch(
            "backend.mlflow_sink.mlflow.get_trace", create=True, return_value=object()
        ):
            results = sink.deliver_many([{"event_id": event_id, "payload": {}} for event_id in ids])
        flush.assert_called_once_with()
        self.assertEqual(results[0]["error"], "ValueError")
        self.assertTrue(results[1]["success"])


if __name__ == "__main__":
    unittest.main()
