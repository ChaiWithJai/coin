from exchange_cycle import ExchangeAssembler, MovementEvent


def event(ms, kind, confidence=0.9, observable=True):
    return MovementEvent(ms, kind, confidence, observable)


def test_complete_exchange_cycle():
    a = ExchangeAssembler()
    for item in [
        event(0, "probe_jab"), event(300, "committed_punch"),
        event(600, "committed_punch"), event(900, "guard_recovered"),
        event(1200, "lateral_exit"),
    ]:
        assert a.accept(item) is None
    result = a.accept(event(1500, "reset"))
    assert result.completed
    assert result.record()["phases"]["interact"]["committed_punch_count"] == 2


def test_unobservable_angle_is_unknown_not_failure():
    a = ExchangeAssembler()
    for item in [
        event(0, "probe_jab"), event(200, "committed_punch"),
        event(400, "committed_punch"), event(600, "guard_recovered"),
        event(800, "lateral_exit", observable=False),
    ]:
        a.accept(item)
    result = a.accept(event(1000, "reset"))
    assert result.record()["phases"]["angle_change"]["observed"] is None
    assert not result.completed


def test_noise_cannot_start_exchange_and_timeout_closes_one():
    a = ExchangeAssembler(maximum_exchange_ms=1000)
    assert a.accept(event(0, "committed_punch")) is None
    assert a.accept(event(100, "probe_jab", confidence=0.2)) is None
    a.accept(event(200, "probe_jab"))
    a.accept(event(1300, "probe_jab"))
    assert len(a.finished) == 1
    assert a.finished[0].end_reason == "timeout"


def test_round_stop_preserves_incomplete_exchange():
    a = ExchangeAssembler()
    a.accept(event(100, "probe_jab"))
    result = a.close_round(500)
    assert result.end_reason == "round_stopped"
    assert not result.completed
