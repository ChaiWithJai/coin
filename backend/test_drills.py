import pytest
from drills import render_selection,eligible

def test_timestamp_and_observation_are_preserved_verbatim():
 note={'seconds':12,'text':'Rear hand stays low after a jab.'}
 result=render_selection([note],0,'guard_return','fr')
 assert result['observation']==note['text'] and result['clip_timestamp_seconds']==12
 assert 'près du visage' in result['drill']

def test_unrelated_notes_cannot_receive_guard_drill():
 with pytest.raises(ValueError):render_selection([{'seconds':1,'text':'Footwork is hidden.'}],0,'guard_return','en')
 assert eligible('ma main arrière est basse')==['review_clip','guard_return']
 with pytest.raises(ValueError):render_selection([],0,'review_clip','fr')
