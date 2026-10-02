from pipeline import CueEngine, Window, Observation

def w(seq=1, captured=10000, source='user_confirmed',lang='fr', session='fixture'):
    return Window(session,seq,captured,lang,(Observation('rear_hand_low',0.99,source,captured),))

def test_expired_and_reordered_never_speak():
    e=CueEngine()
    assert e.process(w(),12000)['reason']=='expired'
    assert e.process(w(),10001)['reason']=='out_of_order'

def test_unconfirmed_vision_cannot_become_coaching():
    assert CueEngine().process(w(source='pose_candidate'),10001)['action']=='silence'

def test_cooldown_is_per_session_and_bilingual():
    e=CueEngine()
    assert e.process(w(),10001)['text']=='Ramène ta main arrière en garde.'
    assert e.process(w(seq=2,captured=11000),11001)['reason']=='cooldown'
    assert e.process(w(lang='en',session='other'),11001)['text']=='Bring your rear hand back to guard.'

def test_future_and_stale_observations():
    e=CueEngine()
    assert e.process(w(),9999)['reason']=='invalid_clock'
    old=Window('fixture',1,10000,'fr',(Observation('rear_hand_low',1,'user_confirmed',7000),))
    assert e.process(old,10001)['action']=='silence'
