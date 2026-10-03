# French source proposal review

Run locally with any complete proposal-only day export:

```sh
python3 tools/translation_review/app.py /absolute/path/to/day-fr-unreviewed.json
```

Open the printed localhost URL. Use `--labels /path/review.json` for an explicit review file, `--db /path/batch.sqlite` to inspect the stored model attempts, and `--port` to choose a port. The default label file sits beside the proposal export. Nothing is sent to Coin or MLflow by this tool. Its decisions are **local reviewer decisions**, not verified boxing gold labels or approved runtime copy. The source JSON must say `runtimeEligible=false`; generated labels retain that gate.

The view joins the proposal to Coin's bundled `ios/WorkoutCatalog.json` by lesson SHA, block ID, item ID, and exact source wording to show the surrounding source section. Use `--catalog` when reviewing against a different exact catalog. A mismatch stops the review instead of displaying unrelated context.

Reviewer keys: `1` pass, `2` fail, `D` defer, `U` undo, arrows navigate, Cmd+S saves, Cmd+Enter saves and advances. A note on an existing decision autosaves after typing. The expandable provenance panel includes model identity, exact source hashes, prompt version, the full item record, and attempts when the batch SQLite is available. Actual cost stays unknown unless provided independently.
