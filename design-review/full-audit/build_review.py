"""Build the Coin mobile atlas in Ray of Light's review JSON format."""
import json
from pathlib import Path

HERE = Path(__file__).parent
SHOTS = HERE / "shots"
STAGES = [
    ("01-home-fr", "entry", "French workout entry"),
    ("02-home-en", "entry", "English workout entry"),
    ("03-live-warmup-en", "live", "English camera and warm-up"),
    ("04-live-round-en", "live", "English boxing round"),
    ("05-recap-en", "review", "English immediate recap"),
    ("06-session-log-en", "review", "English session log"),
    ("07-film-en", "film", "English film notebook"),
    ("08-settings-en", "settings", "English connection settings"),
    ("09-calendar-en", "calendar", "English training calendar"),
    ("10-live-warmup-fr", "live", "French camera and warm-up"),
    ("11-live-round-fr", "live", "French boxing round"),
    ("12-recap-fr", "review", "French immediate recap"),
    ("13-film-fr", "film", "French film notebook"),
    ("14-calendar-fr", "calendar", "French training calendar"),
]

samples = []
for order, (key, flow, title) in enumerate(STAGES):
    assert (SHOTS / f"{key}.png").exists(), key
    samples.append({"id": key, "order": order, "flow": flow, "title": title, "mobile": f"shots/{key}.png"})

notes = [
    # sample, rectangle x/y/w/h normalized to the native 828 x 1792 capture,
    # mode, severity, observation. Rectangle is evidence location, not tap area.
    ("01-home-fr", (.04,.20,.86,.22), "overscaled-display", "P1", "Two-line display title consumes about a quarter of the first screen. The camera start and chosen session sit below a long introduction, making entry feel like reading a poster rather than entering a workout."),
    ("02-home-en", (.04,.20,.88,.15), "overscaled-display", "P1", "The English headline takes nearly the full width and dominates the initial viewport. Reduce its type size and vertical block to bring the start action higher."),
    ("01-home-fr", (.04,.79,.91,.19), "tab-occlusion", "P1", "Floating tab bar overlaps the first training-log row. The log's content continues behind it and is hard to scan or tap."),
    ("02-home-en", (.04,.79,.91,.19), "tab-occlusion", "P1", "Training-log rows appear under the floating navigation bar. Add actual scroll content inset or relocate navigation."),
    ("01-home-fr", (.04,.61,.90,.15), "visual-entropy", "P2", "Duration row, oversized red CTA and explanatory floor-angle paragraph form three stacked calls for attention. Preserve the corner mark, but reduce secondary copy and make the start control the single focus."),
    ("02-home-en", (.04,.61,.90,.15), "visual-entropy", "P2", "Large duration boxes and saturated button compete with the large title. Establish one accent use and a smaller control scale."),
    ("03-live-warmup-en", (.04,.78,.90,.17), "overscaled-live-hud", "P1", "The bottom HUD is tall and the red Start button fills most of its width. The camera area is visually clear in simulator, but usable framing with a real image is unverified."),
    ("04-live-round-en", (.04,.78,.90,.17), "overscaled-live-hud", "P1", "The timer and Pause control dominate the bottom of the camera view. Make the timer and controls compact enough to read at a glance without masking feet or bag action."),
    ("10-live-warmup-fr", (.04,.78,.90,.17), "overscaled-live-hud", "P1", "French warm-up shows the same tall HUD; the longer Commencer label needs a compact, language-safe layout."),
    ("11-live-round-fr", (.04,.78,.90,.17), "overscaled-live-hud", "P1", "Long French drill instruction and full-width Pause button occupy the bottom edge. Verify dynamic type and long drill names before adding more text."),
    ("11-live-round-fr", (.04,.79,.27,.04), "language-leak", "P1", "French live round still labels the stage ROUND 1. Use the selected app language consistently in the camera UI."),
    ("05-recap-en", (.04,.16,.90,.20), "overscaled-display", "P1", "Session saved heading and status summary are much larger than the evidence that matters after a workout; they push the useful round card down."),
    ("05-recap-en", (.04,.32,.90,.20), "metric-ambiguity", "P1", "0 timed rounds appears above a Round 1 reached card. Both are technically distinguishable, but the hierarchy makes the report look self-contradictory. Lead with time trained and rounds reached, then label completed full rounds separately."),
    ("12-recap-fr", (.04,.18,.90,.26), "overscaled-display", "P1", "Séance enregistrée wraps into two very large lines; the actual round evidence starts below the middle of the screen and the next action is pushed to the bottom."),
    ("12-recap-fr", (.04,.45,.91,.09), "french-overflow", "P0", "French stat labels overlap: ÉCHANTILLONS CAMÉRA runs into CONSIGNES DEMANDÉES. Three equal columns do not accommodate the French strings."),
    ("12-recap-fr", (.04,.32,.91,.13), "language-leak", "P1", "French recap still says rounds and drill. Decide whether these are intentional boxing loanwords; current mixed register differs from the rest of the French UI."),
    ("06-session-log-en", (.04,.33,.91,.58), "native-style-drift", "P1", "Dense grouped Form card, large navigation header and repeated planned rows abandon the compact editorial style of the entry and live views. Collapse untouched future rounds and elevate observed segments."),
    ("07-film-en", (.04,.12,.91,.31), "contrast-mismatch", "P0", "White title, subtitle, section labels and status-bar text sit on warm ivory; several are nearly invisible. Correct color tokens before any further styling."),
    ("13-film-fr", (.04,.12,.91,.31), "contrast-mismatch", "P0", "The same white-on-ivory failure hides the French film title and section labels. This persists across both languages."),
    ("07-film-en", (.04,.84,.91,.14), "tab-occlusion", "P1", "Floating tabs cover the Live feedback card, including its explanatory text; the notebook content needs bottom clearance."),
    ("13-film-fr", (.04,.84,.91,.14), "tab-occlusion", "P1", "French notebook's Conseils en direct card is covered by the floating tab bar."),
    ("13-film-fr", (.04,.56,.91,.23), "language-leak", "P1", "Saved film rows retain English fixture titles such as Evaluation clip while the surrounding UI is French; distinguish user-given titles from fixture content and label demos visibly."),
    ("09-calendar-en", (.04,.80,.91,.18), "tab-occlusion", "P1", "The calendar's session rows disappear below the floating tab bar; a day with many logs cannot be scanned from this viewport."),
    ("14-calendar-fr", (.04,.80,.91,.18), "tab-occlusion", "P1", "The French calendar also loses log rows beneath the navigation bar."),
    ("14-calendar-fr", (.04,.68,.91,.22), "language-leak", "P1", "French calendar date pills say Sep and session rows say rounds; month heading alone is localized. Use one French locale for dates and count strings."),
    ("09-calendar-en", (.04,.23,.91,.54), "native-style-drift", "P2", "A single tall system-style card dominates the planning screen, with large blank space beneath the month grid. Distinguish calendar dates from log rows and keep the card proportional to the content."),
    ("08-settings-en", (.04,.20,.91,.55), "technical-frontload", "P2", "Connection settings foreground URL, access key and pose telemetry in a large technical sheet reached from the film notebook. Keep this out of the first-use coaching journey and use compact support copy."),
]

annotations = []
for n, (sample, (x,y,w,h), mode, severity, note) in enumerate(notes, start=1):
    assert sample in {s[0] for s in STAGES}
    assert all(0 <= v <= 1 for v in (x,y,w,h)) and x+w <= 1 and y+h <= 1
    annotations.append({"id": f"coin-full-{n:02d}", "sample": sample,
                        "viewport": "mobile", "rect": {"x":x,"y":y,"w":w,"h":h},
                        "mode": mode, "priority": severity, "note": note,
                        "from": "agent", "ts": 0})

DESCRIPTIONS = {
    "contrast-mismatch": "Light text on the warm ivory film notebook destroys hierarchy and legibility in both languages.",
    "french-overflow": "Fixed three-column metric layout does not fit longer French labels and causes actual overlap.",
    "language-leak": "Selected French language does not propagate to all counts, stage names, date labels and fixture-derived content.",
    "tab-occlusion": "Floating bottom navigation covers lower list rows and cards because screens lack matching bottom scroll clearance.",
    "overscaled-display": "Large title cards consume the first viewport and push the workout or review action/evidence below it.",
    "overscaled-live-hud": "Live bottom overlay uses a larger timer/button stack than needed for glanceable coaching over camera footage.",
    "metric-ambiguity": "A technically precise completed-round count appears contradictory beside a reached-round card.",
    "native-style-drift": "Session log and calendar use bulky system grouped-list proportions instead of the established compact noir language.",
    "visual-entropy": "Too many competing entry elements weaken the one-tap camera start.",
    "technical-frontload": "Technical server controls and telemetry explanations intrude into the consumer film flow.",
}
patterns = []
for mode, description in DESCRIPTIONS.items():
    matched = [a for a in annotations if a["mode"] == mode]
    patterns.append({"mode": mode, "description": description, "count": len(matched),
                     "example_ids": [f'{a["sample"]}/mobile' for a in matched],
                     "example_quotes": [a["note"] for a in matched[:2]]})
patterns.sort(key=lambda p: -p["count"])

for name, value in (("samples", samples), ("annotations", annotations),
                    ("patterns", patterns), ("suggestions", [])):
    (HERE / f"{name}.json").write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
print(f"{len(samples)} live-captured screens; {len(annotations)} rectangle annotations; {len(patterns)} clusters")
