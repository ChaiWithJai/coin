"""Deliver queued session events to MLflow without blocking coaching."""
import uuid

import mlflow
from mlflow import MlflowClient


class MLflowSink:
    """At-least-once delivery with ordered, event-level batch results."""

    def __init__(self, uri="http://127.0.0.1:5210", experiment="boxing-app-inference"):
        mlflow.set_tracking_uri(uri)
        self.client = MlflowClient(uri)
        self.experiment = mlflow.set_experiment(experiment)

    def _finished_run(self, event_id):
        runs = self.client.search_runs(
            [self.experiment.experiment_id],
            filter_string=f"tags.event_id = '{event_id}' and attributes.status = 'FINISHED'",
            max_results=100,
        )
        # A process can die after ending a run but before flushing its trace.
        # Such a FINISHED run is not a delivery receipt and must not suppress a
        # retry. Search all bounded candidates because a later retry may be the
        # first one whose trace became durable.
        for run in runs:
            trace_id = run.data.tags.get("trace_id")
            if trace_id and mlflow.get_trace(trace_id):
                return run
        return None

    @staticmethod
    def _description(payload):
        decision = payload.get("decision", {})
        names = [stage.get("name", "") for stage in payload.get("stages", [])]
        kind = "round_report" if any(name.endswith("round_report") for name in names) else "coaching_event"
        facts = decision.get("facts", {}) if isinstance(decision, dict) else {}
        run_name = (
            f"round {facts.get('round', '?')} · {facts.get('exchanges', '?')} exchanges · {facts.get('main_issue', '')}"
            if kind == "round_report"
            else "queued-coaching-event"
        )
        return decision, facts, kind, run_name

    def _create(self, event_id, payload):
        decision, facts, kind, run_name = self._description(payload)
        tags = {
            "event_id": event_id,
            "record_kind": "durable_event",
            "run_scope": "telemetry_export",
            "delivery_semantics": "at_least_once",
            "product_event_status": str(decision.get("status", decision.get("action", "recorded"))),
            "event_kind": kind,
            "main_issue": str(facts.get("main_issue", "")),
        }
        with mlflow.start_run(run_name=run_name, experiment_id=self.experiment.experiment_id, tags=tags) as run:
            for key in ("exchanges", "punches", "probe_openers", "commit_openers", "reset_rate", "small_model_opener_agreement"):
                if isinstance(facts.get(key), (int, float)):
                    mlflow.log_metric(key, facts[key])
            with mlflow.start_span(name=kind, span_type="CHAIN") as span:
                mlflow.update_current_trace(metadata={"mlflow.trace.session": payload["session_id"], "event_id": event_id})
                span.set_inputs({"window_id": payload.get("window_id"), "captured_at": payload.get("captured_at"), "model_versions": payload.get("model_versions", {})})
                span.set_outputs(decision)
                for stage in payload.get("stages", []):
                    with mlflow.start_span(name=stage["name"], span_type=stage.get("span_type", "TOOL")) as child:
                        child.set_inputs(stage.get("inputs", {}))
                        child.set_outputs(stage.get("outputs", {}))
                        child.set_attribute("observed_duration_ms", stage.get("duration_ms"))
                span.set_attribute("timing_semantics", "Replay time is export time; original stage durations are explicit attributes.")
            trace_id = mlflow.get_last_active_trace_id()
            if not trace_id:
                raise RuntimeError("Trace ID missing")
            mlflow.log_dict(payload, "event.json")
            mlflow.set_tag("trace_id", trace_id)
            return run.info.run_id, trace_id

    def deliver_many(self, events):
        """Create all events, flush once, then verify each created run and trace.

        A crash before lease completion replays safely: FINISHED runs are found
        by stable event ID. Creation and readback failures are isolated so the
        caller can finish successful sibling leases and retry only failures.
        """
        events = list(events)
        results = [None] * len(events)
        created = []
        for index, event in enumerate(events):
            raw_event_id = event["event_id"]
            try:
                event_id = str(uuid.UUID(raw_event_id))
                if self._finished_run(event_id):
                    results[index] = {"event_id": raw_event_id, "success": True, "deduplicated": True}
                    continue
                run_id, trace_id = self._create(event_id, event["payload"])
                created.append((index, raw_event_id, run_id, trace_id))
            except Exception as exc:
                results[index] = {"event_id": raw_event_id, "success": False, "error": type(exc).__name__}

        if created:
            try:
                mlflow.flush_trace_async_logging()
            except Exception as exc:
                error = type(exc).__name__
                for index, event_id, _, _ in created:
                    results[index] = {"event_id": event_id, "success": False, "error": error}
            else:
                for index, event_id, run_id, trace_id in created:
                    try:
                        run = self.client.get_run(run_id)
                        if run.info.status != "FINISHED":
                            raise RuntimeError("Run readback was not FINISHED")
                        if run.data.tags.get("event_id") != str(uuid.UUID(event_id)):
                            raise RuntimeError("Run readback event ID mismatch")
                        if not mlflow.get_trace(trace_id):
                            raise RuntimeError("Trace readback failed")
                    except Exception as exc:
                        results[index] = {"event_id": event_id, "success": False, "error": type(exc).__name__}
                    else:
                        results[index] = {"event_id": event_id, "success": True}
        return results

    def __call__(self, event_id, payload):
        result = self.deliver_many([{"event_id": event_id, "payload": payload}])[0]
        if not result["success"]:
            raise RuntimeError(result.get("error", "MLflow delivery failed"))
