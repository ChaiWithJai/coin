# Coin prototype

Native iPhone boxing film notebook with a GB10 coaching backend in development.

## Xcode

Open `ios/Coin.xcodeproj`. The app targets iOS 16 or newer. It currently imports a video from Files, records up to three minutes through the camera, saves rounds locally, adds timestamped notes, seeks from notes and deletes recordings. French is the default; English is selectable. Live model feedback is not connected yet.

Regenerate the project with `xcodegen generate --spec ios/project.yml` after changing its specification. Build using Xcode or:

```sh
xcodebuild -project ios/Coin.xcodeproj -scheme Coin -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

Unsigned simulator builds do not establish physical-device readiness or TestFlight eligibility. A signing team and validated device build are still required.

## Evidence

MLflow experiments: `boxing-app-trajectory` (development) and `boxing-app-inference` (pipeline/model evidence). Synthetic fixtures are tagged and cannot establish boxing accuracy.

`backend/model-manifest.json` records the observed resident GB10 Bonsai checkpoint and runtime hashes. `backend/probe_bonsai.py` performs a bounded, traced integration request under a shared queue claim. It does not restart the server. Do not run the probe as a benchmark or while training owns the GPU.

`backend/laya_cpu_probe.py` runs on GB10 using an isolated Python environment, pins a Hugging Face revision, hashes downloaded files and evaluates three synthetic intervention cases on CPU. This is a baseline, not a trained boxing policy.

`backend/telemetry.py` provides a SQLite durable outbox with leases and retry backoff. Delivery is at least once. `backend/mlflow_sink.py` reads back exported traces and uses event IDs to suppress already finished duplicate deliveries. Trace export timestamps differ from capture timestamps; original durations are explicitly preserved. The live app and coordinator must still be wired to this outbox.

Canonical direction and readiness gates live in the parent output folder.
