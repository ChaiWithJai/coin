"""Deterministic assembly of classified boxing events into drill exchanges.

Classifiers propose events. This module preserves ordering, visibility and missing
evidence so downstream language models cannot turn an unobserved phase into a miss.
"""
from dataclasses import asdict, dataclass, field
from typing import Literal
import uuid

EventKind = Literal[
    "probe_jab", "committed_punch", "guard_recovered", "lateral_exit", "reset"
]


@dataclass(frozen=True)
class MovementEvent:
    timestamp_ms: int
    kind: EventKind
    confidence: float
    observable: bool = True


@dataclass
class Exchange:
    exchange_id: str
    start_ms: int
    end_ms: int | None = None
    probe_jabs: int = 0
    committed_punches: int = 0
    guard_recovered: bool | None = None
    lateral_exit: bool | None = None
    completed: bool = False
    end_reason: str | None = None

    def record(self) -> dict:
        return {
            "exchange_id": self.exchange_id,
            "start_ms": self.start_ms,
            "end_ms": self.end_ms,
            "phases": {
                "initiate": {"observed": self.probe_jabs > 0, "jab_count": self.probe_jabs},
                "interact": {
                    "observed": self.committed_punches >= 2,
                    "committed_punch_count": self.committed_punches,
                },
                "terminate": {"observed": self.guard_recovered},
                "angle_change": {"observed": self.lateral_exit},
            },
            "completed": self.completed,
            "end_reason": self.end_reason,
        }


@dataclass
class ExchangeAssembler:
    maximum_exchange_ms: int = 8_000
    minimum_confidence: float = 0.7
    current: Exchange | None = None
    finished: list[Exchange] = field(default_factory=list)

    def accept(self, event: MovementEvent) -> Exchange | None:
        if event.timestamp_ms < 0 or not 0 <= event.confidence <= 1:
            raise ValueError("Invalid movement event")
        if event.confidence < self.minimum_confidence:
            return None
        if self.current and event.timestamp_ms < self.current.start_ms:
            return None
        if self.current and event.timestamp_ms - self.current.start_ms > self.maximum_exchange_ms:
            self._finish(event.timestamp_ms, "timeout")

        if event.kind == "probe_jab":
            if self.current is None:
                self.current = Exchange(str(uuid.uuid4()), event.timestamp_ms)
            self.current.probe_jabs += 1
        elif self.current is None:
            return None
        elif event.kind == "committed_punch":
            self.current.committed_punches += 1
        elif event.kind == "guard_recovered":
            self.current.guard_recovered = True if event.observable else None
        elif event.kind == "lateral_exit":
            self.current.lateral_exit = True if event.observable else None
        elif event.kind == "reset":
            if not event.observable:
                return None
            complete = (
                self.current.probe_jabs > 0
                and 2 <= self.current.committed_punches <= 3
                and self.current.guard_recovered is True
                and self.current.lateral_exit is True
            )
            self.current.completed = complete
            return self._finish(event.timestamp_ms, "reset")
        return None

    def close_round(self, timestamp_ms: int) -> Exchange | None:
        return self._finish(timestamp_ms, "round_stopped") if self.current else None

    def _finish(self, timestamp_ms: int, reason: str) -> Exchange:
        assert self.current is not None
        self.current.end_ms = max(timestamp_ms, self.current.start_ms)
        self.current.end_reason = reason
        result = self.current
        self.finished.append(result)
        self.current = None
        return result

