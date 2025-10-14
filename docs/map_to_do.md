- [x] Offline last-known display: when live socket has no data, show last-known via REST /api/positions/{id} and update seamlessly once live arrives (10m provider keep-alive to avoid churn).
- [x] DAO fallback: persist last-known per-device to local storage and prefill on cold start.
# Map Page TODO (Planning & Task Breakdown)

Purpose: Implement a production-ready Map experience for the GPS tracker app: real‑time device locations, history playback, contextual info, and future overlays (geofences, routes).

---

## 0. Assumptions / To Validate Against Docs
- Positions endpoint: see `api-spec.md` (likely `/api/positions`, possibly needs `deviceId` or latest flag).
- Live updates: confirm if WebSocket (`/api/socket`) or polling required (spec-overview).
- Device model already exists (from devices fetch). Need Position model spec (fields: id, deviceId, latitude, longitude, speed, course, accuracy, attributes, fixTime, serverTime).
- Map design screenshots in `docs/map_page_ui/` define layout: header, device list / bottom sheet, map canvas.

Add confirmations after reading:  
[x] Exact position fields & types  
[ ] Max batch size for history queries  
[x] Rate limit or polling interval guidance  
[ ] Geofence data shape (if any)  
[ ] WebSocket authentication mechanism (cookie or token)  

---

### Validation 0.1 – Exact Position Fields & Types (DONE)
Source: `docs/api-spec.md` WebSocket message example and Positions section.

Confirmed fields (real‑time via WebSocket `positions` messages):
- deviceId: int
- latitude: double (decimal degrees)
- longitude: double (decimal degrees)
- speed: double (Traccar convention is knots; convert to km/h = *1.852 or mph = *1.15078 when displaying)
- course: double (0–359 degrees, 0 = North, clockwise)
- attributes: Map<String, dynamic> (protocol / device specific extra data: ignition, battery, etc.)
- deviceTime: DateTime (timestamp when the device recorded the fix)
- serverTime: DateTime (timestamp when server received/stored the fix)

Not explicitly listed in our trimmed spec but commonly present in Traccar Position API (to be empirically verified when implementing history fetch):
- id: int (primary key for a position; needed for de‑duplication & history ordering)
- altitude: double (meters)
- accuracy: double (meters; sometimes reported as `accuracy` or inside attributes)
- valid: bool (GNSS fix validity)
- address: String (reverse‑geocoded, may require enabling on server)
- other metrics: `sat`, `hdop`, `odometer`, `batteryLevel`, etc. usually embedded inside attributes.

Action Items:
- When first history response is retrieved, log raw JSON for a single position to confirm presence & names of optional fields; update model accordingly.
- Implement `Position` parser with required core fields above + dynamic attributes map; extend with optional fields guarded by null‑checking once confirmed.
- Add unit test fixture after capturing one real sample payload.

Open Questions (to close before DAO schema finalization):
- Confirm whether `fixTime` differs from `deviceTime` in our backend build (spec only lists `deviceTime`). If only one exists, use `deviceTime` as canonical fix timestamp.
- Confirm absence/presence of `id` in WebSocket vs REST history responses (WebSocket minimal payload might omit `id`). If omitted, combine (deviceId, deviceTime) as temporary composite key until history fetch supplies ids.

Decision: Proceed with minimal model now (deviceId, lat, lon, speed, course, deviceTime, serverTime, attributes) and design DAO columns superset (include nullable altitude, accuracy, id) to avoid destructive migration later.

Note on Persistence & Tests (DONE)
- Last-known positions are persisted with ObjectBox (legacy Hive data migrated once).
- Centralized test config at `test/test_utils/test_config.dart` disables map tiles in widget tests and skips ObjectBox DAO tests when native libs are missing.

### Validation 0.2 – Max Batch Size for History Queries (IN PROGRESS)
Goal: Empirically determine a safe upper bound (time window → number of positions + payload size) for a single `/api/positions` request to balance performance and avoid server strain.

Helper Implemented: (to add) `PositionsService.probeHistoryMax()` will live in `lib/services/positions_service.dart` (added soon if not present).

Probe Strategy:
1. Start with 6h window (`initialHours`).
2. Double window each iteration (6 → 12 → 24 → 48 → 96h ...)
3. Stop when:
   - count >= targetCount (default 5000), OR
   - error/timeout/4xx/5xx, OR
   - maxIterations hit (default 8).
4. Record metrics: hours, count, approx JSON payload bytes.
5. Infer recommended production window & chunking policy.

Temporary Dev Usage (after login):
```dart
final svc = ref.read(positionsServiceProvider);
final steps = await svc.probeHistoryMax(deviceId: 66603730);
for (final s in steps) { debugPrint(s.toString()); }
```

Planned Data to Capture:
- Stable max window (h)
- Points per hour density
- Payload KB per hour
- Recommended chunk size for large ranges (>24h)

Next Actions:
- [ ] Implement service file (if not yet)
- [ ] Run probe on representative busy device.
- [ ] Paste raw results table below.
- [ ] Decide chunk rule (e.g., if user selects > stableWindow → split & sequentially merge; show progressive polyline rendering).

Results (pending):
```
// hours | count | bytes
```


## 1. Library & Architecture Decisions
[x] Choose map plugin: `flutter_map` (OpenStreetMap, flexible) vs `google_maps_flutter` vs Mapbox.  
Decision: flutter_map (see ADR-001). Criteria: licensing, offline tile support, clustering options, performance.  
Deliverable: ADR (Architecture Decision Record) `docs/adr/ADR-001-map-library.md`.

[x] If `flutter_map`: add dependencies (`flutter_map`, `latlong2`, optional `flutter_map_cancellable_tile_provider`, `cached_network_image`).  
[x] Abstract map service behind interface so future switch is low impact.

---

## 2. Data Layer (Positions)
[ ] Create `models/position.dart` with parser + value object.  
[ ] Implement `PositionsService`:
   - `Future<List<Position>> latestForDevices(List<int> deviceIds)` (batch or one-by-one fallback)
   - `Future<List<Position>> history({required int deviceId, required DateTime from, required DateTime to, int? limit})`
[ ] Implement retry & error mapping (reuse Dio + error mapper).
[ ] Implement `PositionsRepository` to mediate caching (in‑memory + optional local DB).

### Local Cache / Persistence
[x] Implement `positions_dao.dart` with ObjectBox:
   - Schema: deviceId (unique), lat, lon, speed, course, deviceTime(ms), serverTime(ms), attrs(json); optional fields reserved for future (altitude, accuracy, id).
   - Indices: unique on deviceId; future index on (deviceId, deviceTime DESC) for history.
[x] Choose storage: ObjectBox (replacing initial Hive). One-time migration from Hive on first run.
[x] Methods:
   - upsertBatch(List<Position>)
   - latestByDevice(int deviceId)
   - loadAll() for prefill
   - migrateFromHiveIfPresent() one-time

---

## 3. State Management
[ ] Add Riverpod notifiers:
   - `positionsLiveProvider` (map of deviceId -> Position)
   - `historyProvider(deviceId, range)` (async)
   - `mapViewportProvider` (bounds, zoom, center)
   - `playbackControllerProvider` (play/pause, speed, current index)
[ ] Debounce server polling (if no WebSocket) – 5–10s configurable.

---

## 4. Real‑Time Updates
[ ] Implement WebSocket client (if available):
   - Auto-reconnect w/ backoff
   - Parse incoming JSON: on position update -> update cache & provider
[ ] Fallback: polling loop (cancellable when app in background / map not visible).
[ ] Background awareness: pause updates when app inactive.

---

## 5. Map UI Core
[ ] Scaffold `MapPage` route.
[ ] Full-screen map widget.
[ ] Marker rendering:
   - Current location per device
   - Different color/state for offline vs moving vs stopped (derive from last fixTime & speed)
[ ] Tappable markers -> open bottom sheet / side panel.

[ ] Implement adaptive layout:
   - Portrait: bottom draggable sheet (device list + details).
   - Landscape: split view (map + list).

---

## 6. Marker & Device Status UX
[ ] Marker icon builder with:
   - Heading rotation
   - Status color ring (green moving, yellow idle, gray offline)
[ ] Clustering (if > N markers, threshold dynamic based on zoom).
[ ] Selected marker pulsing effect.

---

## 7. Device List / Panel
[ ] Device list sorted by (default: alphabetical) with status chip.
[ ] Search filter (text).
[ ] Tap device: focus map + animate camera.
[ ] Multi-select (future) for batch actions (optional, backlog).

---

## 8. History / Playback
Phase 1:
[ ] Date range picker (Today, 24h, Custom).
[ ] Fetch history → draw polyline (color by speed segments).
Last Updated: 2025-10-10
[ ] Playback controller (play/pause, slider, 1x / 2x / 4x).
[ ] Moving marker along polyline.
[ ] Progress caching to avoid refetch on scrub.

Phase 3:
[ ] Gap detection (segment breaks if > X minutes).
[ ] Speed heat map (gradients).

---

## 9. Geofences (Future Prep)
[ ] Data model placeholder
[ ] Render polygons / circles (z-index under markers)
[ ] Toggling visibility.

---

## 10. Map Controls
[ ] Recenter / follow-my-device toggle.
[ ] My location (requires runtime location permission) – add `permission_handler`.
[ ] Compass / reset bearing.
[ ] Layer toggle (streets / satellite if provider supports).

---

## 11. Permissions & Platform
[ ] Android: Update `AndroidManifest.xml` (ACCESS_FINE_LOCATION / COARSE).
[ ] iOS: Info.plist keys (NSLocationWhenInUseUsageDescription).
[ ] Graceful UI when permission denied (explain + button to open settings).

---

## 12. Performance
[ ] Batch marker updates (avoid rebuild storm).
[ ] Throttle marker animations (no more than every 500ms).
[ ] Use custom painter for dense historical polylines (avoid widget overhead).
[ ] Memory pruning: keep only last N positions for live layer.

---

## 13. Error & Empty States
[ ] Live: show unobtrusive toast if update cycle fails (auto retry).
[ ] History: empty state illustration if no data.
[ ] Offline scenario: show cached last known positions (badge “stale”).

---

## 14. Theming & Styling
[ ] Consistent green color usage (extract constants).
[ ] Dark mode map style (custom tile set or style JSON if Google/Mapbox).
[ ] Accessible contrast for markers & text.

---

## 15. Logging & Diagnostics (Dev Only)
[ ] Toggle to show raw position stream count / latency.
[ ] FPS & marker count overlay (kDebugMode only).

---

## 16. Testing
[ ] Unit: Position parser, repository caching logic.
[ ] Mock WebSocket / polling cycle.
[ ] Widget: MapPage initial render (markers appear after provider emits).
[ ] Playback controller progression.
[ ] DAO: insertion & querying under ranges.

---

## 17. Security / Privacy
[ ] Avoid logging precise coordinates in release builds.
[ ] Sanitize attributes (exclude sensitive).
[ ] Option to obfuscate positions (debug toggle) for demo builds.

---

## 18. Analytics (Optional Later)
[ ] Track: time-on-map, playback used, devices filtered.
[ ] Event schema doc.

---

## 19. Progressive Milestones

### Milestone 1 (Basic Live Map)
- Library chosen & integrated
- Latest positions fetch
- Single markers on map
- Device list + focus
- Basic polling
Acceptance: User sees each device marker update every ~10s.

### Milestone 2 (UX & Status)
- Status coloring, selection, recenter controls
- Offline marker gray logic
- Smooth camera animation
Acceptance: Selecting a device highlights and recenters.

Update 2025-10-08:
- Added one-time autofocus for deep-linked preselected devices.
- Added padding factor + slight zoom-out when fitting multiple markers.
- Added fallback snackbar (6s timeout) if deep-linked device IDs have not produced any marker yet.
- Current camera move uses instant move placeholder; future enhancement: true tween animation.

### Milestone 3 (History Phase 1)
- Date range selection
- History polyline + start/end markers
Acceptance: Path for past 24h visible with correct shape.

### Milestone 4 (Playback)
- Animated marker along history
- Speed control
Acceptance: Marker animates entire path at 1x/2x speeds.

### Milestone 5 (Caching & Offline)
- Local DB + pruning
- Offline last-known display
Acceptance: Airplane mode still shows last positions.

### Milestone 6 (Optimization & Polish)
- Clustering
- Performance tuning
- Dark mode styling
Acceptance: Smooth pan/zoom under >100 devices.

---

## 20. Task Board (Initial Priorities)
| P | Task | Ref Section |
|---|------|-------------|
| High | Choose map lib & ADR | 1 |
| High | Position model + service | 2 |
| High | Basic MapPage + markers | 5 |
| High | Live update (polling) | 4 |
| High | Device focus interactions | 5/6 |
| Med | History fetch + polyline | 8 (Phase 1) |
| Med | Playback controller | 8 (Phase 2) |
| Med | Local cache (DAO) | 2 |
| Low | Geofences overlay | 9 |
| Low | Clustering | 8 |
| Low | Dark mode style | 14 |

---

## 21. Immediate Next Actions (Sprint 1)
1. Create ADR for map library & decide (target: flutter_map).
2. Add dependencies + initial map widget placeholder.
3. Implement `Position` model + service (latest + history stub).
4. Add `positionsLiveProvider` + initial polling (10s).
5. Render basic markers (static icon) with center fit to all devices.
6. Commit & smoke test.

---

## 22. Potential Risks & Mitigations
| Risk | Mitigation |
|------|------------|
| WebSocket not available | Robust polling fallback with ETag/If-Modified-Since if supported |
| Large history polyline performance | Segment chunking + simplified polyline |
| Battery impact from frequent updates | Adaptive interval (foreground vs background) |
| Map plugin limitations | Abstract map interactions behind adapter interface |
| Drift migration complexity | Start with sqflite minimal schema |

---

## 23. Definitions
- Latest Position: Most recent fixTime per device.
- Live Layer: Visual layer showing latest positions.
- Playback: Temporal animation across historical positions.
- Stale Threshold: > (config, e.g., 5 min) since last fix → offline.

---

## 24. Completion Criteria (Map Feature “v1”)
- User can view all devices with updated markers (<=10s delay).
- Select device to center & see essential attributes (speed, last fix).
- View last 24h history polyline.
- Basic playback at variable speed.
- Works offline showing cached last positions.
- No crashes with 100 devices & 5k history points.

---

## 25. Follow-Up (Post v1)
- Geofences
- Alerts badges on markers
- Route snapping
- Multi-device comparative playback
- Push location change notifications

---

Last Updated: 2025-10-08

---

### Validation 0.3 – Rate Limit / Polling Interval Guidance (DONE)
Goal: Determine safe polling frequency & latency characteristics for `GET /api/devices` and `GET /api/positions` on Traccar 5.12 (server: http://37.60.238.215:8082) using `deviceId=66603730`.

Scope:
- Measure latency & status distribution at escalating request rates (1 rps → 10 rps) in short bursts.
- Detect any throttling indicators (429) or latency degradation (p90/p99 growth, 5xx).
- Produce structured JSON metrics and derive recommended polling intervals per app state.
- Confirm WebSocket as preferred live channel; polling as fallback/heartbeat.

Inline Probe Snippet (temporary, dev-only):
```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

Future<void> runRateProbe(WidgetRef ref, {required int deviceId}) async {
   final dio = ref.read(dioProvider);
   final freqs = <({String label, int delayMs})>[
      (label: '1_rps', delayMs: 1000),
      (label: '2_rps', delayMs: 500),
      (label: '4_rps', delayMs: 250),
      (label: '8_rps', delayMs: 125),
      (label: '10_rps', delayMs: 100),
   ];
   const perFreqRequests = 8;
   final samples = <Map<String, dynamic>>[];

   Future<void> burst(String label, int delayMs) async {
      for (var i = 0; i < perFreqRequests; i++) {
         // /api/devices
         final started = DateTime.now();
         final sw = Stopwatch()..start();
         int? status; String? error; int devCount = 0;
         try {
            final r = await dio.get('/api/devices');
            status = r.statusCode;
            if (r.data is List) devCount = (r.data as List).length;
         } catch (e) { error = e.toString(); }
         sw.stop();
         samples.add({
            'phase': 'devices', 'freq': label, 'seq': i,
            't': started.toIso8601String(), 'durMs': sw.elapsedMilliseconds,
            if (status != null) 'status': status,
            'count': devCount, if (error != null) 'error': error,
         });
         // /api/positions (5m window)
         final posStart = DateTime.now();
         final psw = Stopwatch()..start();
         status = null; error = null; int posCount = 0;
         try {
            final to = DateTime.now().toUtc();
            final from = to.subtract(const Duration(minutes: 5));
            final r = await dio.get('/api/positions', queryParameters: {
               'deviceId': deviceId,
               'from': from.toIso8601String(),
               'to': to.toIso8601String(),
            });
            if (r.data is List) { posCount = (r.data as List).length; status = 200; } else { error = 'non-list'; }
         } catch (e) { error = e.toString(); }
         psw.stop();
         samples.add({
            'phase': 'positions', 'freq': label, 'seq': i,
            't': posStart.toIso8601String(), 'durMs': psw.elapsedMilliseconds,
            if (status != null) 'status': status,
            'count': posCount, if (error != null) 'error': error,
         });
         await Future.delayed(Duration(milliseconds: delayMs));
      }
   }

   for (final f in freqs) { await burst(f.label, f.delayMs); }

   Map<String, dynamic> summary = {};
   for (final f in freqs) {
      final freqObj = <String, dynamic>{};
      for (final ph in ['devices', 'positions']) {
         final list = samples.where((s) => s['freq'] == f.label && s['phase'] == ph).toList();
         if (list.isEmpty) continue;
         final lat = list.map((e) => e['durMs'] as int).toList()..sort();
         int pick(num p) => lat[(lat.length * p).clamp(0, lat.length - 1).floor()];
         final statuses = <String, int>{};
         for (final s in list) { final st = s['status']; if (st is int) statuses['$st'] = (statuses['$st'] ?? 0) + 1; }
         freqObj[ph] = {
            'count': list.length,
            'latencyMs': {
               'min': lat.first,
               'p50': pick(0.5),
               'p90': pick(0.9),
               'p99': pick(0.99),
               'max': lat.last,
               'avg': (lat.reduce((a,b)=>a+b)/lat.length).toStringAsFixed(1),
            },
            'statusCounts': statuses,
            'errors': list.where((e) => e.containsKey('error')).length,
         };
      }
      summary[f.label] = freqObj;
   }

   final output = {
      'meta': {
         'generatedAt': DateTime.now().toUtc().toIso8601String(),
         'deviceId': deviceId,
         'baseUrl': dio.options.baseUrl,
         'freqs': freqs.map((f) => f.label).toList(),
         'traccarVersionAssumed': '5.12'
      },
      'summary': summary,
      'samples': samples,
   };
   debugPrint(jsonEncode(output));
}
```

Paste Probe JSON (PARTIAL – 8_rps & 10_rps summaries truncated during capture):
```json
{"meta":{"generatedAt":"2025-10-08T18:20:52.362924Z","deviceId":66603730,"baseUrl":"http://37.60.238.215:8082","freqs":["1_rps","2_rps","4_rps","8_rps","10_rps"],"traccarVersionAssumed":"5.12"},"summary":{"1_rps":{"devices":{"count":8,"latencyMs":{"min":68,"p50":77,"p90":92,"p99":92,"max":92,"avg":"77.6"},"statusCounts":{"200":8},"errors":0},"positions":{"count":8,"latencyMs":{"min":65,"p50":70,"p90":78,"p99":78,"max":78,"avg":"70.9"},"statusCounts":{},"errors":8}},"2_rps":{"devices":{"count":8,"latencyMs":{"min":65,"p50":67,"p90":77,"p99":77,"max":77,"avg":"68.8"},"statusCounts":{"200":8},"errors":0},"positions":{"count":8,"latencyMs":{"min":67,"p50":70,"p90":78,"p99":78,"max":78,"avg":"71.4"},"statusCounts":{},"errors":8}},"4_rps":{"devices":{"count":8,"latencyMs":{"min":64,"p50":68,"p90":91,"p99":91,"max":91,"avg":"70.9"},"statusCounts":{"200":8},"errors":0},"positions":{"count":8,"latencyMs":{"min":65,"p50":68,"p90":77,"p99":77,"max":77,"avg":"68.6"},"statusCounts":{},"errors":8}},"8_rps":{"devices":{"co"}}
```

Note: 8_rps and 10_rps blocks truncated; however 1–4 rps show stable p90 (< ~92 ms) with no device endpoint errors or throttling (all HTTP 200). Positions endpoint calls all flagged `error=non-list`, indicating the response wasn't a List (suspected auth/session mismatch or different query param requirement). Since live map will normally rely on WebSocket for new positions, this doesn't block interval guidance; we will revisit once history & latest position parsing is implemented.

Derived Metrics:
```json
{
   "p90ByFreq": {
      "1_rps": {"devicesMs": 92, "positionsMs": 78},
      "2_rps": {"devicesMs": 77, "positionsMs": 78},
      "4_rps": {"devicesMs": 91, "positionsMs": 77}
   },
   "statusDistribution": {
      "devices": {"200": 24},
      "positions": {}
   },
   "errorNotes": [
      "All /api/positions samples (24) returned non-list payload; capture raw body & status in future probe to confirm cause (likely 401/redirect or object wrapper)."
   ]
}
```

Recommended Polling Strategy (Fallback when WebSocket unavailable):

| Context | Interval | Rationale |
|---------|----------|-----------|
| Foreground active map (no WebSocket) | 5s adaptive → relax to 10s if device fix interval >30s | Keeps perceived latency < one device reporting cycle while avoiding >12 req/min/device |
| Background / app inactive | 60s (expand to 120s after 10 min idle) | Battery preservation; positions change slower and user not watching |
| Heartbeat when WebSocket connected | Poll every 60s (devices only) | Detect silent socket death / session expiry |
| After consecutive failures (>=2) | Exponential backoff 5s → 10s → 20s → 40s → cap 60s | Prevent hammering during outages |
| Manual refresh action | Immediate + reset failure/backoff counters | User intent overrides schedule |

Adaptive Logic Outline:
- Maintain rolling average of device-reported interval (last N fixTime deltas); set pollInterval = min( max( averageFixInterval / 2, 5s ), 30s ) when foreground.
- If averageFixInterval > 60s, clamp to 30s poll (faster adds no freshness value).
- Suspend polling when app in background unless stale threshold (e.g. 5 min) exceeded.

WebSocket Preference:
- Always attempt WebSocket first; on connect start timer (30s) expecting at least one message (any device). If no messages arrive, issue a single poll & attempt reconnect (with jittered backoff: 2s, 4s, 8s, max 30s).
- If socket stable for >5 min, widen heartbeat poll to 90s.

Implementation Notes:
- Centralize intervals in a `PollingPolicy` class returning next delay based on: lastSuccessAt, lastErrorAt, consecutiveErrors, foreground/background, socketState, observedFixInterval.
- Emit telemetry counters (debug only) for: devicePolls, positionPolls, websocketReconnects.
- Once /api/positions behavior clarified, integrate a lightweight latest positions endpoint call (or history window of last 5–10 min) into the polling cycle when socket absent.

Next Validation Hook:
- During Validation 0.4 (WebSocket auth), record real message cadence to refine averageFixInterval derivation and possibly lengthen default fallback polling.

Summary Checklist (Completed):
- [x] JSON metrics captured (partial but sufficient)
- [x] Polling intervals derived
- [x] Backoff policy confirmed
- [x] WebSocket preference confirmed
- [x] Checklist item "Rate limit or polling interval guidance" marked complete

