import importlib
import sys
import uuid

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from telemetry import Outbox


def test_pose_window_is_durable_idempotent_and_silent(tmp_path, monkeypatch):
    token_file = tmp_path / 'token'
    token_file.write_text('fixture-token-' + 'x' * 32)
    monkeypatch.setenv('COIN_TOKEN_FILE', str(token_file))
    sys.modules.pop('service', None)
    service = importlib.import_module('service')
    monkeypatch.setattr(service, 'DATA', tmp_path)
    monkeypatch.setattr(service, 'OUTBOX', Outbox(tmp_path / 'events.db'))
    body = service.PoseWindow(
        request_id=uuid.uuid4(), session_id=uuid.uuid4(), block_id=uuid.uuid4(),
        sequence=4, sampled_at_ms=1000, language='fr', landmark_count=33,
        visible_landmark_count=12, framing_ready=False, capture_to_pose_ms=38.5,
        camera_facing='back', wrist_travel_body_widths=0.42,
        lower_body_visible=False,
        source_version='mediapipe-pose-full-v1',
    )
    first = service.pose_window(body)
    assert first == service.pose_window(body)
    assert first['action'] == 'silence'
    assert first['reason'] == 'movement_classifier_unvalidated'
    assert first['event_id'] == str(body.request_id)
    assert service.OUTBOX.counts() == {'pending': 1}
    event = service.OUTBOX.claim()
    assert event['payload']['stages'][0]['name'] == 'visual_perception'
    assert event['payload']['stages'][0]['outputs']['visible_landmark_count'] == 12
    assert event['payload']['stages'][0]['inputs']['camera_facing'] == 'back'
    assert event['payload']['stages'][0]['outputs']['wrist_travel_body_widths'] == 0.42
    assert event['payload']['stages'][0]['outputs']['lower_body_visible'] is False
    assert event['payload']['model_versions']['motion_feature'] == 'wrist-travel-v1'
    with pytest.raises(HTTPException) as collision:
        service.pose_window(body.model_copy(update={'visible_landmark_count': 13}))
    assert collision.value.status_code == 409
    with pytest.raises(HTTPException) as invalid:
        service.pose_window(body.model_copy(update={'visible_landmark_count': 34}))
    assert invalid.value.status_code == 422
    with pytest.raises(ValidationError):
        service.PoseWindow(**{**body.model_dump(), 'landmark_count': 34})


def test_laya_candidate_and_policy_have_separate_telemetry_stages(tmp_path, monkeypatch):
    token_file = tmp_path / 'token'
    token_file.write_text('fixture-token-' + 'x' * 32)
    monkeypatch.setenv('COIN_TOKEN_FILE', str(token_file))
    sys.modules.pop('service', None)
    service = importlib.import_module('service')
    monkeypatch.setattr(service, 'DATA', tmp_path)
    monkeypatch.setattr(service, 'OUTBOX', Outbox(tmp_path / 'events.db'))
    class FakeAgent:
        def predict(self, state, questions):
            return {'answers': {'intervention': {'choice': 'cue', 'confidence': 0.5}}}
    monkeypatch.setattr(service, 'agent', FakeAgent())
    body = service.Decision(request_id=uuid.uuid4(), session_id=uuid.uuid4(),
                            state='synthetic fixture', visible=True, cooldown_clear=True)
    result = service.decide(body)
    assert result['action'] == 'quiet'
    event = service.OUTBOX.claim()
    assert [stage['name'] for stage in event['payload']['stages']] == [
        'laya_model_call', 'system1_cue_policy']
    assert event['payload']['stages'][0]['duration_ms'] >= 0
    assert event['payload']['stages'][1]['outputs']['action'] == 'quiet'
