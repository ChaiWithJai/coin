"""Run frozen synthetic contract cases against the existing private Laya coordinator.

Runs on GB10 with the local token file. Never promotes a candidate to a live cue.
"""
import hashlib
import json
import time
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATASET = ROOT / "system1-contract-cases-v1.json"
TOKEN = Path("/home/chaiwithjai/Documents/code/coin-boxing/service-token")
ENDPOINT = "http://127.0.0.1:5290/v1/decide"


def run():
    raw = DATASET.read_bytes()
    dataset = json.loads(raw)
    results = []
    for case in dataset["cases"]:
        body = {"request_id": str(uuid.uuid4()), "session_id": str(uuid.uuid4()),
                "state": json.dumps({"source_kind": "synthetic_contract_case",
                                     "protocol_id": dataset["protocol_id"],
                                     "language": case["language"],
                                     **case["state"]}, sort_keys=True, ensure_ascii=False),
                "visible": case["visible"], "cooldown_clear": case["cooldown_clear"]}
        request = urllib.request.Request(ENDPOINT, data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json",
                     "Authorization": "Bearer " + TOKEN.read_text().strip()})
        start = time.perf_counter()
        with urllib.request.urlopen(request, timeout=30) as response:
            result = json.load(response)
        elapsed = (time.perf_counter() - start) * 1000
        candidate = (result.get("candidate") or {}).get("answers", {}).get("intervention", {})
        expect_model = case["policy_expectation"] == "candidate_only"
        passed = (result.get("action") == "quiet"
                  and (bool(candidate) == expect_model)
                  and (result.get("source") == ("unpromoted_laya_candidate" if expect_model else "deterministic_veto")))
        results.append({"case_id": case["id"], "language": case["language"],
                        "expectation": case["policy_expectation"], "contract_passed": passed,
                        "action": result.get("action"), "source": result.get("source"),
                        "candidate_choice": candidate.get("choice"),
                        "candidate_confidence": candidate.get("confidence"),
                        "candidate_answer_confidence": candidate.get("answer_confidence"),
                        "usage": (result.get("candidate") or {}).get("usage"),
                        "round_trip_ms": round(elapsed, 1), "event_id": result.get("event_id")})
    return {"dataset_id": dataset["dataset_id"], "dataset_sha256": hashlib.sha256(raw).hexdigest(),
            "source_kind": dataset["source_kind"], "case_count": len(results),
            "contract_pass_count": sum(item["contract_passed"] for item in results),
            "model_accuracy": None, "actual_billed_usd": None,
            "results": results}


if __name__ == "__main__":
    print(json.dumps(run(), indent=2, ensure_ascii=False))
