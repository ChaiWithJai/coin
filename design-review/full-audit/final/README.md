# Final three-surface check

I installed the latest `/tmp/coin-derived/Build/Products/Debug-iphonesimulator/Coin.app` on the booted iPhone 11 simulator, launched it, and captured the settled French Sessions, Vidéos and Calendrier screens. This checks the later changes that were absent from the `after/` pass.

| Surface | Result | Evidence |
| --- | --- | --- |
| Sessions home | **Occlusion fixed for the current entry state.** Journal shows one latest session, fully above the floating tabs. Date is localized as `26 sept. 2026`. The corner-post mark remains present. | [French home](01-home-fr.png) |
| Film notebook | **Occlusion fixed for the current entry state.** Removing profile controls leaves saved film rows clear above tabs. Noir contrast remains readable. Two stored fixture titles still say `Evaluation clip` in the French screen; they should be visibly identified as demo data or renamed at fixture creation without rewriting user titles. | [French film](02-film-fr.png) |
| Calendar | **Partially improved.** The compact date picker brings the selected day and six session rows into view. With the existing many-session simulator dataset, additional rows still visually continue under the floating tab bar. CUA scroll attempts did not move the Form, so this pass cannot prove the last rows are reachable. Add and verify bottom clearance for long days. | [French calendar](03-calendar-fr.png) |

The three files are current 828 × 1792 simulator captures. This pass did not repeat the live workout, English, settings, or physical-camera checks; their status remains as recorded in the earlier `after/` report. The simulator cannot validate camera framing or MediaPipe feedback against real training footage.
