import hashlib
import json
from pathlib import Path


def test_protocol_sources_and_bilingual_cues_are_versioned():
    catalog = json.loads((Path(__file__).parent / "boxing-drill-library-v1.json").read_text())
    assert catalog["library_version"] == "coin-boxing-drills-v1"
    protocol = catalog["protocols"][0]
    assert protocol["id"] == "probe-combine-angle-v1"
    assert protocol["engagement_phases"] == ["initiate", "interact", "terminate", "reset"]
    assert protocol["live_cue_policy"]["max_cues_at_once"] == 1
    assert protocol["live_cue_policy"]["quiet_on_uncertainty"]
    for cue_id in protocol["live_cue_policy"]["allowed_cue_ids"]:
        if cue_id != "quiet":
            assert set(protocol["cue_copy"][cue_id]) == {"fr", "en"}
    for source in protocol["provenance"]:
        path = Path(source["path"])
        assert hashlib.sha256(path.read_bytes()).hexdigest() == source["sha256"]
        data = json.loads(path.read_text())
        available = {item["id"] for item in (data["foundations"] if isinstance(data, dict) else data)}
        assert set(source["source_ids"]) <= available
        assert "training_label" not in source["role"] or source["role"].startswith("curriculum")
