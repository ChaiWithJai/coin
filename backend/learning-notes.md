# Development observations

## 25 September 2026: first model probes

Bonsai 27B, pinned ternary GGUF on resident GB10 service: one synthetic user-confirmed text observation produced schema-valid French JSON. Shared-service HTTP duration was 9.63 seconds. This is not a video result or isolated latency benchmark. The limitation text introduced sparring and pain even though the request described solo shadowboxing. Next prompt intervention: require an evidence limitation tied to the input, avoid unrelated activities, and evaluate French and English matched cases. Preserve the original response.

Laya 0.3.20, pinned multilingual weights, GB10 CPU: three synthetic decision cases all selected cue. Only the first was expected to cue; occlusion and active cooldown should remain silent. Warm calls were approximately 137 and 141 ms; first call approximately 250 ms. Three cases cannot establish deployment latency or population accuracy. The confident cooldown error means a confidence threshold alone is insufficient.

Implementation consequence: ordering, expiry, visibility and cooldown are deterministic vetoes. Laya may rank eligible issues; it may not override those vetoes. Gather corrected cue/no-cue examples and temporal evidence before training. Evaluate false cues and missed useful cues separately. Model-generated labels remain proposals.

Telemetry: SQLite outbox survives process reconstruction; simulated network failure retries after backoff; expired leases can be reclaimed; stale workers cannot acknowledge someone else's lease. Synthetic event export to MLflow was read back. Delivery is at least once, not an exactly-once guarantee. Original timings are attributes because replay trace timestamps describe export time.

Coordinator prompt v2 correctly stated its note-based limitation but turned a note at second 12 into a twelve-second action. Preserve coordinator-review-result.json. Next intervention uses observation_index and reconstructs observation/timestamp directly from original notes; model generation is restricted to drill and limitation. This prevents rewritten-observation fabrication by construction, but drill grounding still needs evaluation.


Coordinator v3 prevented timestamp rewriting but returned English for a French request. V4 fixed language but suggested keeping the rear hand low. Schema validity is not coaching correctness. The current contract lets Bonsai select only an observation index and an eligible drill ID. The server preserves the original note and renders fixed bilingual text. The small drill library is authored for development and still needs qualified coaching review.

The simulator imported a private development clip, saved a deliberately marked test note about feet outside the frame, requested a GB10 review, and displayed the fixed French replay drill. The result persisted in the app and its queued inference event exported to MLflow run 76b3b5af4a7141f49996e0e13430539d. This verifies integration, not automatic video analysis or coaching quality. Screenshot review exposed truncated drill text; the round screen now scrolls and allows full text height.

Request snapshots now persist before transmission and reuse the same request ID after a lost response or restart. Changed notes, language or endpoint produce a new request. A standalone Swift test verifies these cases. Server conflicts are surfaced for investigation rather than generating a replacement ID. Round deletion removes its local request snapshots; remote retention and deletion remain unfinished.


## Multilingual correction

Saved reviews now render the current drill library in the selected language without a new inference. Optional drill IDs preserve compatibility with older saved reviews; exact known library text can recover their ID. Unknown older free-form advice prompts regeneration instead of displaying the wrong language. User notes and filenames retain their original text. Localized connection errors, explicit Edit/Done labels, singular note counts, SwiftUI locale updates, refreshed row actions and French/English permission descriptions were added.

Validation: simulator build passed; Swift checks passed for French-to-English legacy text, English-to-French drill IDs, unknown legacy fallback, request retry persistence and endpoint isolation. UI verified English rendering of the saved French review and English Delete action after reload. System permission dialogs still use the device app language. No new model inference was required.

## 25 September 2026 (Claude Code session): first visual perception evidence

Handoff: the Codex session ended on a 401 from its API credential. Claude Code continued. Mac MLflow (bonsai-lab, port 5210) had stopped at 19:02 and was restarted with its original arguments; experiments 39 and 40 were intact.

Apple Vision body pose (VNDetectHumanBodyPoseRequest) ran over all 383 s of IMG_0951 at 10 fps in 65 s on the Mac host. Analyzer runs are MLflow `guard-analyzer-v{1,2,3}-img0951` in boxing-app-inference; labels are analyst single-frame inspection, not coach truth, and this video is development data.

- v1 (bare-hand thresholds, raw normalized coordinates): 5 rear-hand-low candidates; 4 were walking, wrapping hands and putting on gloves. It also judged a distant gym-goer after the camera swung.
- v2 (lead-hand posture gate, larger minimum body size): no false candidates but judged 2 of 384 windows and lost the one plausible drop. Vision places the wrist at the glove cuff, so a correct gloved guard still sits about 0.22 shoulder-widths below the shoulder line.
- Measured, aspect-corrected: guard median 0.22 (p90 0.26); wrapping 0.37; gloving 0.37; the likely drop at 253 s 0.35. Wrist speed at 10 fps does not separate wrapping from boxing either. **Pose geometry alone cannot tell whether the person is boxing.**
- v3: aspect-corrected distances, too-close/too-small/multiple-people framing reasons, threshold 0.32 (provisional; one positive), and boxer-supplied round bounds. Inside 150-384 s: one candidate at 253 s, guard windows correctly silent, **coverage 2.6%**.

Product consequences: (1) round boundaries come from the boxer (live start/stop, or marking the round on an imported clip), not from pose; (2) the main blocker is camera placement, so the app now reports analysable coverage and framing advice; (3) the next data need is a tripod-mounted, 2-3 m, whole-upper-body solo bag round with a coach or boxer marking real dropped-hand moments. Confirmed candidates become user notes; rejections are stored locally as future negative labels but are not yet exported to MLflow.
