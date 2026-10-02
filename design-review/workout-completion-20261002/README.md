# Coin workout completion verification

Verified on October 2, 2026, in the Coin iPhone 11 simulator, device `CB5D7882-F35E-469E-980B-5729D3C0F7D4`. The target was `Coin` and the application was `com.coinboxing.prototype`. No physical phone was installed or changed.

The combined run passed 41 unit tests and five workout UI tests. Its result is `/tmp/coin-workout-derived/Logs/Test/Test-Coin-2026.10.02_18-28-07--0400.xcresult`; the log is `/tmp/coin-workout-completion-tests.log`.

The tests completed a manual source workout, opened its original instructions, saved it, restarted the app, verified program progress, and reopened the saved record. They also let a short freestyle timer finish, saved a reflection, restarted, and reopened the reflection. Existing checks reached day 35 in both programs, restored an exact two-minute source round, and verified French and English freestyle controls.

An extra pending-review assertion initially failed because the simulator has no camera exchanges, so normal runtime correctly creates no round report. That result is retained at `/tmp/coin-workout-derived/Logs/Test/Test-Coin-2026.10.02_18-30-54--0400.xcresult`.

The follow-up run passed all 41 unit tests and the focused freestyle UI test, including the pending final-round card in the recap and after reopening. Its result is `/tmp/coin-workout-derived/Logs/Test/Test-Coin-2026.10.02_18-32-36--0400.xcresult`; the log is `/tmp/coin-workout-pending-review-fixture-tests.log`. This run includes the report client's write-failure retention change.

That final card is explicitly a UI fixture. It is seeded only in a DEBUG build with `COIN_TEST_ROUND_REVIEW=1`, a valid isolated `workout-ui-` directory token, and service URL exactly `http://127.0.0.1:1`. Its source ID prevents network dispatch. The ten-second timer is also a DEBUG fixture. All UI tests override the service URL and token; none submit synthetic input to GB10.

The five PNG files here were exported from those test results and visually inspected. Source labels and full instructions are readable, manual work appears in the recap, and the pending review appears in both review surfaces. Source instructions remain English. This evidence establishes UI completion, local persistence, and offline review rendering. It does not establish physical movement recognition, source exercise completion, model quality, or a successful gym workout.

To rerun the complete suite from `ios/`:

```sh
xcodebuild -workspace Coin.xcworkspace -scheme Coin \
  -destination 'platform=iOS Simulator,id=CB5D7882-F35E-469E-980B-5729D3C0F7D4' \
  -derivedDataPath /tmp/coin-workout-derived \
  -only-testing:CoinTests -only-testing:CoinUITests/WorkoutFlowTests test
```

After this simulator review, the matching signed Coin build was installed and launched on Lakshmi. See `../../evidence/workout-delivery-20261002/completion-checkpoint.json` for the later phone receipt.
