/// Centralized performance thresholds for regression checks.
/// Adjust these as the app evolves; tests should import from here.
/// These constants are used by performance tests and optionally by runtime diagnostics UI.

// Target average frames per second. In CI/unit-test environments where
// frame timings are not available, FPS checks may be skipped.
const int kTargetFps = 50;

// Maximum acceptable backfill latency in milliseconds.
const int kMaxBackfillMs = 5000;

// Maximum acceptable time for cluster computation in milliseconds.
const int kMaxClusterMs = 150;

// Maximum acceptable number of deduplicated (skipped) events in a short window.
const int kMaxDedupSkip = 5;

// Maximum acceptable WebSocket ping latency in milliseconds.
const int kMaxPingMs = 300;
