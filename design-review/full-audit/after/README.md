# Follow-up visual check — installed simulator build

I installed `/tmp/coin-derived/Build/Products/Debug-iphonesimulator/Coin.app` on the same booted iPhone 11 simulator and repeated the French/English entry → live warm-up → boxing round → early finish/recap → film → calendar path. These screenshots are the **after** state for the baseline atlas in the parent folder. The parent was editing the home log again during this check; the later single-row home change is **not** in this installed build.

| Baseline failure | Result in installed build | After evidence |
| --- | --- | --- |
| White text on ivory film notebook (P0) | **Fixed.** Notebook now uses noir background, cream heading, readable muted copy and dark cards in both languages. | [English](07-film-en.png), [French](13-film-fr.png) |
| French recap labels collide (P0) | **Fixed.** Two stat columns fit `Échantillons caméra` and `Consignes demandées` without overlap. | [French recap](12-recap-fr.png) |
| Oversized entry and recap (P1) | **Improved.** Entry headline is one line, start action sits higher; recap title is one line and first round card is visible without scrolling. Introductory prose and duration row still make entry more text-heavy than the desired one-tap camera flow. | [French entry](01-home-fr.png), [English entry](02-home-en.png), [recap](12-recap-fr.png) |
| Oversized live HUD (P1) | **Improved modestly.** Timer and button are smaller; center of preview remains clear. The red action still spans most of the width, and black simulator preview cannot prove safe composition over a real boxer. | [English round](04-live-round-en.png), [French round](11-live-round-fr.png) |
| English `ROUND 1` in French live view (P1) | **Fixed.** It now reads `REPRISE 1`. | [French round](11-live-round-fr.png) |
| French calendar `Sep` pills and `rounds` count (P1) | **Fixed.** Date pills read `26 sept.` and counts read `reprises`. | [French calendar](14-calendar-fr.png) |
| `0 timed rounds` beside one reached round (P1) | **Improved.** Summary now explicitly says `0 rounds finished` / `0 reprises terminées`; below, the round is labeled reached/started. This is understandable as an early finish. | [English recap](05-recap-en.png), [French recap](12-recap-fr.png) |
| Floating tabs cover lower content (P1) | **Still visible.** A home training-log row is behind the tab bar in this build; the film stance control and calendar session rows are also covered. Drag/scroll attempts did not visibly bring the covered content clear in this check. The parent has since changed home to one latest row, so recapture that separately. | [Home](01-home-fr.png), [film](13-film-fr.png), [calendar](14-calendar-fr.png) |
| Saved film fixture names in French (P1) | **Still visible.** `Evaluation clip` remains in a French notebook. This may be stored user/fixture content; mark demo entries clearly or migrate fixture names without rewriting user-given titles. | [French film](13-film-fr.png) |
| Mixed French register (P1) | **Mostly improved.** Live, recap and calendar use `reprise`; film still deliberately uses `round`, and recap note placeholder still says `prochain round`. Editorial choice remains unresolved. | [French film](13-film-fr.png), [French recap](12-recap-fr.png) |
| Bulky native session log, technical settings (P2) | **Not rechecked** in this after walk. No completion claim. | Baseline screenshots remain in `../shots/`. |

No new P0 visual regression appeared in the screens checked. The remaining high-priority visual issue is bottom content occlusion on film and calendar. A real iPhone camera pass is still needed for preview legibility, pose overlay alignment, and live cue timing.
