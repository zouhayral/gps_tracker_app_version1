# Prompt 6B.1 — FMTC Migration (Finalize Tile Provider API)

Date: 2025-10-19
Branch: map-core-stabilization-phase6a

## Objective
Migrate from the deprecated `FMTCStore(...).getTileProvider()` to the new `FMTCTileProvider` API introduced in FMTC v10+, preserving behavior and compatibility.

## Summary of Changes
- Replaced deprecated calls in `lib/features/map/view/flutter_map_adapter.dart`:
  - Before:
    - `FMTCStore(storeName).getTileProvider(httpClient: _httpClient, loadingStrategy: ...)`
  - After:
    - `FMTCTileProvider(stores: { storeName: null }, httpClient: _httpClient, loadingStrategy: ...)`
- Removed the file-level `deprecated_member_use` ignore.
- Ensured HTTP client and loading strategy parity with previous behavior.
- Kept per-source store naming (e.g., `tiles_<id>`, `overlay_<id>`) to avoid collisions.

## Rationale
- `FMTCTileProvider` is the modern, forward-compatible API and replaces the deprecated `getTileProvider()` method.
- Using `stores: { '<store-name>': null }` targets a single store with default `BrowseStoreStrategy`, matching old behavior.
- We continue to use a dedicated shared `IOClient` (HTTP/1.1) via `TileNetworkClient.shared()` for reliability and OSM compliance.

## Behavior Parity
- Loading policy mirrors prior logic:
  - Online: `BrowseLoadingStrategy.onlineFirst`
  - Offline: `BrowseLoadingStrategy.cacheOnly`
- Headers/User-Agent continuity is ensured via `TileNetworkClient.userAgent` passed to `TileLayer.userAgentPackageName` and the underlying `IOClient`'s userAgent.
- Per-layer provider caching preserved to avoid flicker and churn.

## Verification
- Analyzer: `flutter analyze --no-pub` → No issues found.
- Tests: `flutter test --no-pub` → All tests passed (ObjectBox tests skipped in this environment by design).
- Runtime signals (from tests): FMTC warmups logged; cache mode toggles printed; no deprecated warnings.

## Impact
- Removes deprecated API usage, preparing for FMTC v11+.
- No functional changes; identical tile loading and caching behavior.

## Future Work
- Consider explicit `BrowseStoreStrategy` tuning if future policies need differentiation.
- Revisit docs/inline comments after any FMTC version upgrade.

## Diff Sketch (illustrative)

Before:
- `FMTCStore(store).getTileProvider(httpClient: _httpClient, loadingStrategy: X)`

After:
- `FMTCTileProvider(stores: { store: null }, httpClient: _httpClient, loadingStrategy: X)`

No other files required code changes.
