import json

from evaluate_framing import evaluate, frame_ready, GATES


def test_upper_body_visibility_does_not_count_as_full_body(tmp_path):
    joints = [{'x': .5, 'y': .5, 'visibility': .9} for _ in range(33)]
    for index in (25, 26, 27, 28):
        joints[index]['visibility'] = .1
    frame = {'clip_seconds': 0, 'poses': [{'landmarks': joints}]}
    assert frame_ready(frame, GATES['upper_body'])
    assert not frame_ready(frame, GATES['full_body'])
    path = tmp_path / 'poses.json'
    path.write_text(json.dumps([{**frame, 'clip_seconds': second} for second in (0, .1, .6)]))
    result = evaluate(path, 'fixture')
    assert result['visibility_gates']['upper_body']['sustained_ready_frames'] == 1
    assert result['visibility_gates']['full_body']['sustained_ready_frames'] == 0
