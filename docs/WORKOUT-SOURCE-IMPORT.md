# Workout source import

Coin now has an offline catalog of the two five-week programs from boxing.dharmicdata.org. The importer uses the site's original workout sections and keeps their text, links, and source identifiers. It does not ask a model to invent a workout duration.

## Source and scope

The 70 saved HTML pages are in:

`/Users/jaibhagat/Documents/antigravity/hybrid-ai-blueprints/.claude/worktrees/shadowbox-demo/blueprints/shadowbox-coach/pipeline/raw`

This is the existing source capture used by the Shadowbox Coach pipeline. It is an archived rendered snapshot. The original website repository has not been located. BrowserOS Neo's current basic week 1, day 1 page contains all 30 imported workout text items unchanged after whitespace normalization. The current homepage confirms two programs and 70 days. These two checks do not establish that every other source page is unchanged. The older `lessons.v1.json` extract drops prescription context, so this import reads the full HTML instead.

Each catalog day keeps its canonical lesson URL, PDF URL, snapshot filename, and SHA-256. Each playable block keeps the source section, original text items, demonstration links, and any other linked references. Endurance workouts with Google Doc references retain those links.

The generated catalog contains 70 days and 535 blocks. There are 233 blocks with an explicit timer and 302 blocks that require the athlete to advance them. Timed blocks may expand into several rounds. The two exact `CONDITIONING DRILL (4 MINUTES)` prescriptions run as one four-minute timer each. A manual block can contain several sets or exercises; it is not a claim that the app recognizes each exercise. Two source sections with distinct prescriptions were split at exact source-item boundaries; no source item or demo link was changed.

## Prescription rules

- Explicit rounds and durations become timers. A source prescription of four two-minute rounds with 30 seconds of rest stays four two-minute rounds with 30 seconds between them.
- Missing rest stays unspecified. The importer does not copy a nearby rest prescription onto another drill.
- Sets, repetitions, mixed circuits, and ambiguous timing stay manual with the original instructions. For example, the source typo `3O SECONDS` does not become an assumed 30-second rest.
- Source sections sometimes put strength and endurance exercises inside elements marked `header`. Those exercises are retained. Basic week 1, day 6 includes its squat, Pallof press, hip airplanes, and other strength prescriptions.
- Daily lifestyle checklists, nutrition advice, productivity tips, and motivational copy do not enter the workout coach. Exclusions keep source IDs, text, and a reason in the catalog.
- Imported boxing blocks use the free-boxing policy. They do not inherit the jab, combination, angle-exit fault policy unless a future reviewed mapping explicitly selects it.
- Exact generic dynamic warm-ups and stretches are runtime mobility slots. Coin pauses before the slot and asks for the concrete movement so pose and timer evidence do not attach to a generic label. The source wording remains unchanged.

Every one of the 2,709 nonempty source items is accounted for exactly once: 1,773 items are in workout blocks and 936 have recorded exclusions. This establishes capture coverage, not recognition accuracy or perfect prescription interpretation.

## Verification and remaining experience work

Ten Python checks pass. They cover the 70-day identity grid, source-item accounting, retained strength and endurance work, source links, first-day timing, unspecified rests, mixed prescriptions, the two reviewed source-section splits, and recovery days. Run them from `server` with `python3 -m unittest test_workout_catalog.py`.

The simulator passed 40 unit tests and 3 UI tests, including both program catalogs, manual completion, exact round timing, restart persistence, and French/English freestyle. Source session summaries now show elapsed time without a zero-minute total. The home screen restores the source workout title, and freestyle no longer displays a provisional probe/commit label. The remaining experience limits are:

1. The source wording is English. French mode needs reviewed French cues and instructions while preserving the original source text and prescription. The current speech path explicitly uses English for source instructions.
2. Mixed strength sections remain manual. Their full instructions and demonstrations are available from the live view, but the next refinement should make each exercise clear without requiring repeated browsing during the workout.
3. Simulator results do not establish camera tracking, cue usefulness, or performance during a physical workout. The signed phone build and a gym session must verify that experience.

These are integration findings, not a request to replace the existing noir camera experience.

## Development loop reference

The recovered authoritative reference is section 5, “How it gets built: development as an agent trajectory,” in [the supplied master plan](https://gist.github.com/ChaiWithJai/74b46c72aefdba34bc1e4dbcb00b3387). Its local copy is `/Users/jaibhagat/code/bonsai-gen/gists/5-boxing/BOXING-MASTER-PLAN.md`, starting at line 145.

It calls for work toward a goal, timed check-ins that record progress and failures, observable exchanges and model decisions, installation on the phone, then a real gym session and feedback driving the next update. Sections 6 and 7 specify measuring cue usefulness, latency, reports, and where small models help. This search did not find a separate named mathematical formula; it would be inaccurate to invent one and attribute it to Jai.

For this import, that loop means preserve the workout source, run it through Coin, inspect the resulting traces and experience, label failures, then improve the specific parser, recognition step, or cue responsible. Model annotation proposals remain separate from source timing and repetitions.
