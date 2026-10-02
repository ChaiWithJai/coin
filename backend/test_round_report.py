import pytest
from pydantic import ValidationError

from round_report import AcceptedAttempt, ReportProposal, report_gate, validate_proposal


def accepted(attempt_id="attempt-1"):
    return AcceptedAttempt(attempt_id=attempt_id, protocol_id="probe-combine-angle-v1",
                           accepted_by_boxer=True, start_ms=100, end_ms=1600,
                           observed_phases=["initiate", "interact"], correction="I stepped out of frame")


def test_no_accepted_attempts_blocks_model_in_both_languages():
    assert report_gate([], "fr")["status"] == "insufficient_evidence"
    assert report_gate([], "en")["model_called"] is False


def test_report_proposal_must_cite_accepted_attempt():
    proposal = ReportProposal(observation="Attempt completed all phases.",
                              interpretation="The opening was repeatable in these attempts.",
                              next_constraint_id="exit_and_reset",
                              prediction="The next round should show more reviewed angle exits.",
                              evidence_attempt_ids=["attempt-1"])
    result = validate_proposal(proposal, [accepted()], "fr")
    assert result["evidence_source"] == "boxer_accepted_attempts"
    assert result["next_constraint_id"] == "exit_and_reset"
    assert "ligne" in result["next_constraint"]
    assert result["model_wording_used"] is False
    assert result["observed_phase_counts"]["reset"] == 0
    assert "all phases" not in result["observation"]
    with pytest.raises(ValueError):
        validate_proposal(proposal.model_copy(update={"evidence_attempt_ids": ["invented"]}),
                          [accepted()], "en")


def test_candidate_cannot_enter_accepted_report():
    with pytest.raises(ValidationError):
        AcceptedAttempt(attempt_id="x", protocol_id="probe-combine-angle-v1",
                        accepted_by_boxer=False, start_ms=0, end_ms=100,
                        observed_phases=["initiate"])
