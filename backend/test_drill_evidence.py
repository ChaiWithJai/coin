from pathlib import Path

from drill_evidence import profile, profile_files

ROOT = Path(__file__).resolve().parents[3]


def frame(ms, visible):
    names = ("leftShoulder", "rightShoulder", "leftWrist", "rightWrist",
             "leftHip", "rightHip", "leftAnkle", "rightAnkle")
    return {"timeMs": ms, "people": [{name: {"confidence": 0.9 if name in visible else 0.1}
                                       for name in names}]}


def test_real_close_bag_clip_abstains_on_angle_exit():
    result = profile_files(ROOT / "work/posecli/frames.json",
                           ROOT / "work/fixtures/personal-bag-15s.mp4")
    assert result["frame_count"] == 150
    assert result["joint_visible_frames"]["leftAnkle"] == 0
    assert result["joint_visible_frames"]["rightAnkle"] == 0
    assert result["system1_route"] == "abstain_unobservable"
    assert result["system2_route"] == "insufficient_visual_evidence"
    assert not result["laya_called"] and not result["bonsai_called"]


def test_temporal_coverage_gate_needs_consecutive_frames():
    names = {"leftShoulder", "rightShoulder", "leftWrist", "rightWrist",
             "leftHip", "rightHip", "leftAnkle", "rightAnkle"}
    intermittent = [frame(i * 100, names if i % 2 == 0 else set()) for i in range(12)]
    assert not profile(intermittent, "synthetic")["drill_coverage_sufficient"]
    continuous = [frame(i * 100, names) for i in range(6)]
    result = profile(continuous, "synthetic")
    assert result["drill_coverage_sufficient"]
    assert result["system2_route"] == "requires_human_labels"
    assert result["engagement_classification"] == "not_attempted"
