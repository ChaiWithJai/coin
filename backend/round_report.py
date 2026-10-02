"""Grounding contract for a deliberate next-round boxing report."""
from typing import Literal
from pydantic import BaseModel, Field, model_validator

PROTOCOL = "probe-combine-angle-v1"
CONSTRAINTS = {
    "probe_then_commit": {
        "fr": "Ouvre chaque échange avec un jab visible avant ta combinaison.",
        "en": "Open each exchange with a visible jab before the combination.",
    },
    "exit_and_reset": {
        "fr": "Après la combinaison, sors de la ligne puis retrouve ta position.",
        "en": "After the combination, leave the line and regain your position.",
    },
    "repeat_and_review": {
        "fr": "Répète le drill et marque un échange à revoir entre les reprises.",
        "en": "Repeat the drill and mark one exchange to review between rounds.",
    },
}


class AcceptedAttempt(BaseModel):
    attempt_id: str = Field(min_length=1)
    protocol_id: Literal["probe-combine-angle-v1"]
    accepted_by_boxer: Literal[True]
    start_ms: int = Field(ge=0)
    end_ms: int = Field(gt=0)
    observed_phases: list[Literal["initiate", "interact", "terminate", "reset"]] = Field(min_length=1)
    correction: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def interval_valid(self):
        if self.end_ms <= self.start_ms:
            raise ValueError("Attempt end must follow start")
        return self


class ReportProposal(BaseModel):
    observation: str = Field(min_length=1, max_length=300)
    interpretation: str = Field(min_length=1, max_length=300)
    next_constraint_id: Literal["probe_then_commit", "exit_and_reset", "repeat_and_review"]
    prediction: str = Field(min_length=1, max_length=300)
    evidence_attempt_ids: list[str] = Field(min_length=1, max_length=5)


def report_gate(attempts: list[AcceptedAttempt], language: Literal["fr", "en"]) -> dict:
    if language not in ("fr", "en"):
        raise ValueError("Unsupported language")
    if not attempts:
        return {
            "status": "insufficient_evidence", "model_called": False,
            "message": "Pas assez d'échanges confirmés pour un bilan technique. Revois un passage entre les reprises."
                       if language == "fr" else
                       "Not enough confirmed exchanges for a technical report. Review one moment between rounds.",
            "accepted_attempt_ids": [],
        }
    ids = [attempt.attempt_id for attempt in attempts]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate accepted attempt ID")
    return {"status": "ready_for_model", "model_called": False, "accepted_attempt_ids": ids}


def validate_proposal(proposal: ReportProposal, attempts: list[AcceptedAttempt], language: Literal["fr", "en"]) -> dict:
    gate = report_gate(attempts, language)
    if gate["status"] != "ready_for_model":
        raise ValueError("Report has no accepted evidence")
    known = set(gate["accepted_attempt_ids"])
    if len(set(proposal.evidence_attempt_ids)) != len(proposal.evidence_attempt_ids) or not set(proposal.evidence_attempt_ids) <= known:
        raise ValueError("Report cites missing or duplicate evidence")
    cited = [attempt for attempt in attempts if attempt.attempt_id in proposal.evidence_attempt_ids]
    counts = {phase: sum(phase in attempt.observed_phases for attempt in cited)
              for phase in ("initiate", "interact", "terminate", "reset")}
    if proposal.next_constraint_id == "probe_then_commit" and counts["initiate"] == len(cited) and counts["interact"] == len(cited):
        raise ValueError("Opening constraint has no missing phase evidence")
    if proposal.next_constraint_id == "exit_and_reset" and counts["terminate"] == len(cited) and counts["reset"] == len(cited):
        raise ValueError("Exit constraint has no missing phase evidence")
    target = "reset" if proposal.next_constraint_id == "exit_and_reset" else (
        "initiate" if proposal.next_constraint_id == "probe_then_commit" else "interact")
    if language == "fr":
        observation = (f"{len(cited)} échanges confirmés : ouverture {counts['initiate']}, combinaison {counts['interact']}, "
                       f"sortie {counts['terminate']}, retour en position {counts['reset']}.")
        interpretation = "Ces phases décrivent les passages confirmés, pas la qualité du mouvement ni le contact."
        phase_fr = {"reset": "retour en position", "initiate": "ouverture", "interact": "combinaison"}[target]
        prediction = f"À la prochaine reprise, vérifie si les phases « {phase_fr} » confirmées augmentent."
    else:
        observation = (f"{len(cited)} confirmed attempts: opening {counts['initiate']}, combination {counts['interact']}, "
                       f"exit {counts['terminate']}, reset {counts['reset']}.")
        interpretation = "These phases describe confirmed intervals, not movement quality or contact."
        prediction = f"Next round, check whether the count of confirmed {target} phases increases."
    result = {"observation": observation, "interpretation": interpretation,
              "next_constraint_id": proposal.next_constraint_id, "prediction": prediction,
              "evidence_attempt_ids": proposal.evidence_attempt_ids,
              "observed_phase_counts": counts}
    result.update(status="evidence_linked_proposal", protocol_id=PROTOCOL,
                  next_constraint=CONSTRAINTS[proposal.next_constraint_id][language],
                  evidence_source="boxer_accepted_attempts",
                  model_wording_used=False)
    return result
