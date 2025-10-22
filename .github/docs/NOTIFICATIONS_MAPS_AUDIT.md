# Notifications & Maps Audit (Baseline)

Last updated: 2025-10-21

## Executive summary

- Build, analyze, and all tests pass on Flutter 3.35.6 / Dart 3.9.2.
- Notifications: stable UI and actions, per-device reconnect backfill with replay anchor, deduplication, and user-facing recovery banner.
- Maps: tile source switching is stable; marker rebuilds are scoped and throttled; offline mode supported with cache-first behavior.
- Next mile: add lightweight instrumentation counters and tidy a few analyzer infos. No functional blockers identified.

## Environment

- OS: Windows
- Flutter: 3.35.6 (stable)
- Dart: 3.9.2
- Package manager: `flutter pub`

## Quality gates

- Build: PASS (via tasks)
- Analyze: PASS (no errors; only info-level hints)
- Tests: PASS (all tests green)

## System overview (current design)

- Realtime ingress: Traccar WebSocket → VehicleDataRepository merges live positions/events.
- Backfill on reconnect: per-device, bounded window, safety margin, dedup by event id.
- Persistence: ObjectBox (events/positions), SharedPreferences (small state; replay anchor).
- Notifications pipeline: NotificationsRepository streams enriched events, dedups, and persists.
- UI banners: live “New” events and post-reconnect recovered events.
- Maps: FlutterMap adapter with cached tile providers, offline/online switching, marker dedup and rebuild isolation.

## Key components and responsibilities

- lib/core/data/vehicle_data_repository.dart
  - Handles WebSocket reconnect; computes safe [from,to] window; per-device `EventService.fetchEvents`.
  - Throttles backfill invocation to prevent duplicate runs.
  - Emits recovered events counts to a banner channel.
- lib/services/event_service.dart
  - Fetches events by deviceId with fallback to `/api/reports/events` on 404/405.
  - Persists to ObjectBox; exposes `getReplayAnchor()` and latest cached timestamps.
- lib/repositories/notifications_repository.dart
  - Streams notifications, maintains dedup set and replay anchor, listens to backfilled events.
- lib/features/map/view/flutter_map_adapter.dart
  - Manages tile provider lifecycle, offline cache mode, and marker layer rebuilds.

## Reliability & correctness checks

- Reconnect backfill
  - Input: last replay anchor (SharedPreferences/ObjectBox), device list, current time.
  - Output: per-device event list, deduped and persisted; recovered count for banner.
  - Edge cases handled: backend 404 on global events, clock skew via safety window, duplicated reconnect triggers (throttled).
- Notifications dedup
  - Set-based id filter in repository; applies equally to live and backfilled events.
- Marker rendering
  - Filters invalid LatLng; dedups by id + selection; isolates repaint via ValueListenable and RepaintBoundary.

## Performance notes

- Marker rebuild frequency is driven by a ValueNotifier and diffed cache, minimizing full map rebuilds.
- Tile provider caching prevents flicker on source toggles; timestamp cache-busting ensures correctness.
- Backfill safety window widened (~5 minutes) to reduce gaps at minimal cost.

## Instrumentation plan (low-overhead)

Emit debug logs and/or counters (Riverpod providers or a simple in-memory singleton) for:

- NOTIF_BACKFILL_REQUEST {deviceId, from, to, count}
- NOTIF_BACKFILL_APPLIED {inserted, deduped}
- NOTIF_DEDUP_SKIPPED {eventId}
- WS_RECONNECT {ts, reason}
- MAP_MARKER_BUILD {count, droppedInvalid, droppedDuplicates}
- MAP_TILE_SWITCH {providerId, ts}
- CONNECTIVITY_STATE {offline→online/online→offline, ts}

Surface optional counters in a hidden diagnostics panel (debug menu) and keep them behind `kDebugMode` guards.

## Analyzer infos worth tidying (non-blocking)

- Directive ordering in a few files (organize imports).
- Prefer `Offset.zero` in constants; replace deprecated `.withOpacity` in older widgets.
- One or two unawaited futures hints – review for intentional fire-and-forget.

## Validation evidence (this session)

- flutter pub get → success
- flutter analyze → no errors; info-only
- flutter test → all tests passed
- build_runner build → completed; analyze & test still PASS

## Risk register

- Backend variability: some Traccar setups return 404 for global `/api/events`. Mitigated by mandatory per-device backfill.
- Time skew: device timestamps vs. server vs. client. Mitigated by safety window and anchor persistence.
- Offline caches: ensure user agent and network client are accepted by tile providers; logs added for failure modes.

## Roadmap (short-term)

1) Implement the lightweight counters above and surface a simple Dev Diagnostics page.
2) Clean up analyzer infos; run `dart fix` where safe.
3) Add a smoke test to assert banner button label is "New" (if UI stabilizes the banner again).
4) Optional: add a profile-mode trace to capture marker build time at 500+ markers.

## Appendix: How to run locally

- Preferred: VS Code tasks in this repo
  - "pub get + analyze + test"
  - "build_runner + analyze + test"

- Optional CLI (Windows PowerShell):
  - flutter pub get ; flutter analyze ; flutter test
