"""Boxing cue contract. Rules baseline; model adapters are separate interventions."""
from dataclasses import dataclass, asdict
from typing import Literal
import time
import mlflow

@dataclass(frozen=True)
class Observation:
    kind: Literal['rear_hand_low', 'feet_crossed', 'unknown']
    confidence: float
    source: Literal['user_confirmed', 'pose_candidate']
    timestamp_ms: int

@dataclass(frozen=True)
class Window:
    session_id: str
    sequence: int
    captured_ms: int
    language: Literal['fr', 'en']
    observations: tuple[Observation, ...]

CUES = {
    'rear_hand_low': {'fr': 'Ramène ta main arrière en garde.', 'en': 'Bring your rear hand back to guard.'},
    'feet_crossed': {'fr': 'Garde tes appuis séparés.', 'en': 'Keep your feet apart.'},
}

class CueEngine:
    """One instance per stream; all timestamps use the same injected clock domain."""
    def __init__(self, max_age_ms=1500, cooldown_ms=5000):
        self.max_age_ms=max_age_ms
        self.cooldown_ms=cooldown_ms
        self.last_sequence={}
        self.last_cue={}

    @mlflow.trace(name='live_window', span_type='CHAIN')
    def process(self, window: Window, now_ms: int):
        mlflow.update_current_trace(metadata={'mlflow.trace.session':window.session_id,
                                             'pipeline_version':'rules-baseline-v1',
                                             'inference_mode':'no-model-baseline'})
        if not window.session_id or window.sequence < 0 or window.language not in ('fr','en'):
            raise ValueError('Invalid window identity or language')
        age=now_ms-window.captured_ms
        if age<0: return self.silent('invalid_clock',age)
        if window.sequence<=self.last_sequence.get(window.session_id,-1):
            return self.silent('out_of_order',age)
        self.last_sequence[window.session_id]=window.sequence
        if age>self.max_age_ms:return self.silent('expired',age)
        if now_ms-self.last_cue.get(window.session_id,-10**15)<self.cooldown_ms:
            return self.silent('cooldown',age)
        selected=self.select(window)
        if selected is None:return self.silent('insufficient_evidence',age)
        self.last_cue[window.session_id]=now_ms
        return {'action':'cue','text':CUES[selected.kind][window.language],
                'observation':asdict(selected),'age_ms':age,'expires_ms':window.captured_ms+self.max_age_ms,
                'decision_source':'rules-baseline-v1','sequence':window.sequence}

    @mlflow.trace(name='evidence_gate', span_type='TOOL')
    def select(self, window):
        for obs in window.observations:
            if not 0<=obs.confidence<=1:raise ValueError('Invalid confidence')
            if obs.timestamp_ms>window.captured_ms:continue
            if window.captured_ms-obs.timestamp_ms>self.max_age_ms:continue
            if obs.source=='user_confirmed' and obs.kind in CUES:return obs
        return None

    @staticmethod
    def silent(reason,age):return {'action':'silence','reason':reason,'age_ms':age,'decision_source':'rules-baseline-v1'}
