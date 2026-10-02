# Coin visual recheck, 26 September 2026

This is a second, source-bound pass over the iPhone 11 simulator evidence after the first full audit. I read `outputs/BUILD-PLAN.md`, `outputs/STATUS.md`, the local Ray of Light style review guidance at `/Users/jaibhagat/code/prismml/bonsai-monitor-demo/tools/design-review/SKILL.md`, and the prior 14-screen atlas. I launched the installed app headlessly and captured `01-home-fr.png` (the filename is historical; **the screen is English**). The Mac locked before direct UI interaction, so I wrote a temporary XCTest journey that captured fresh French home, film, calendar, warm-up, round, recap, and session log screens. It also navigated to the day log, verified a back control, and returned to Sessions. Prior atlas images are referenced only to establish before/after. The parent edited source during this review, so the latest captures are labeled by build.

The [rectangle inventory](annotations.json) names visible regions on the exact screenshots. Coordinates are fractions of each 828 × 1792 image. Findings below are clustered by the user burden they create, then ordered by priority. The [current English home](02-home-latest.png), [French home](03-home-fr.png), [French film](14-film-fr.png), [French live round](09-round-fr-latest.png), [French recap](12-recap-fr.png), [final calendar](19-calendar-final.png), and [final day log](18-day-log-final.png) are all rendered simulator evidence.

## Resolved in installed build — camera action competed with editorial hierarchy

The previous installed [English entry](01-home-fr.png) placed `ENTER THE SESSION` over 60% down the screen, after a large title, intro, voice action, and giant drill. The [rebuilt screen](02-home-latest.png) puts duration choices around y=509–583 and the CTA at y=607–694, only 34–39% down the viewport. The drill and voice action follow. This materially fixes the camera-first hierarchy while preserving the corner-post logo. The intro still takes two lines, but it no longer blocks the main action. The [French entry](03-home-fr.png) was also captured by the headless journey.

## Resolved in installed build — film notebook used a different grammar

The previous [French film screen](../full-audit/final/02-film-fr.png) had a two-line slogan, gray rounded slabs, and import before filming. The [fresh French capture](14-film-fr.png) shows a single compact line, hairline rows, filming first, and the first saved clip in view. This is much closer to the flat noir home grammar. It retains the original corner-post icon elsewhere. The film wording now consistently uses `reprise`; saved video titles remain untouched user data.

## Resolved in installed build — calendar gave weak evidence priority

The earlier calendar had a large gray card, repeated zero-round rows, a blank band, and tab overlap. The [final calendar](19-calendar-final.png) now shows a compact serif title, one meaningful session row, and a collapsed `Plan du camp` below. That row leads with `00:17 au chrono`, with completion status secondary. The [final day log](18-day-log-final.png) sorts 00:17, 00:13, and 00:08 attempts above zero-time attempts and uses elapsed time as its primary label. The test followed `Voir les 13 séances du jour` and verified a visible back control. This is a material fix. The many 00:00 development sessions remain in the day log; grouping or clearing only disposable fixture sessions would make a future real history easier to scan, but it is not a blocker for this visual pass.

## P2 — live camera HUD needs physical composition proof

The [fresh French round](09-round-fr-latest.png) has a smaller timer and controls than the prior capture, with the center of the simulator preview clear. It preserves a compact current cue. The red start button remains wide, which supports touch while training; whether it obscures feet or angle exits cannot be judged on a black simulator preview. Acceptance: establish overlay safe bounds on actual floor, side, and bag placements with iPhone 11; keep one short cue and timer legible; controls never obscure the motion needed for the drill. Pause must remain reachable.

## P2 — recap and log still make the user translate evidence

The [fresh French recap](12-recap-fr.png) says `0 reprises terminées · 00:00 / 30 min` above `REPRISES ENTAMÉES` showing round 1 at 00:00. This particular test ended immediately, so the data are consistent, but the first viewport still makes zero completion the story. It also asks for a free-text note after a coach-led session. The fresh [session log](11-session-log-fr-latest.png) is flatter, yet `0 reprises terminées` and a technical caveat precede the reached round. Acceptance: lead with actual trained time, then `1 reprise entamée`, then full completions; offer one suggested next action only if evidence supports it, otherwise a concise prompt to record a better round. Keep uncertainty visible but shorter.

## Resolved in installed build — French editorial terms were mixed

French live stage and date formatting were repaired in the earlier pass. The [latest film screen](14-film-fr.png) now uses `reprise` in the slogan, film action, import action, and list heading, matching history. `Jab` remains a standard boxing term. Saved video titles remain in their original language, as they should. A short bilingual glossary is still useful to stop this drift from returning.

## P3 — subtle token and scale mismatches

Gold labels on near-black, cream serif headlines, and vermilion CTA form a recognizable system on the entry screen. The film and calendar cards have been flattened, but the selected calendar date uses a subdued brown-gold fill while the entry duration chip uses flat gold. This is a remaining token mismatch, not a contrast failure. Define a shared selection style and recheck the two screens side by side.

## Evidence limits

The simulator was booted and the installed app launched at 12:58. I rebuilt repeatedly as source changed; `xcodebuild` passed with one pre-existing warning in `PoseAnalysis.swift` (`try` around a non-throwing call). Headless XCTest made a fresh French journey possible despite the locked Mac. The English route was only recaptured at home; the prior atlas contains the full English journey. The temporary screenshot tests were removed after capture. The final normal suite passed **20/20 tests** with no failures (`FullSuiteFinal2.xcresult`). Actual camera composition, sound, MediaPipe overlay, and cue timing require the physical iPhone 11. No production app code was edited in this sub-agent review.
