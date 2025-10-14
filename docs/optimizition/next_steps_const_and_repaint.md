# Next Steps: Const, Repaint, and Smooth UI

A concise, high-impact checklist to make the app faster and smoother. Each task lists a clear goal and a concrete action. Tick them off as you land them.

---

## 1) 🧱 Add const constructors everywhere safe

- [x] Const-ify common UI primitives
  - Goal: Reduce rebuild work and GC churn for immutable widgets.
  - Action: In `lib/features/map/view/map_page.dart` and shared widgets, add `const` to SizedBox, Padding, EdgeInsets, BorderRadius/Radius, Duration, Curves, Icon, and Text with static strings.

- [x] Promote const in helper widgets
  - Goal: Prevent unnecessary re-instantiation of leaf widgets.
  - Action: Make constructors `const` where fields are final and no side-effects (e.g., `_ActionButton`, `_InfoLine`, small stateless tiles/cards) and use them as `const` at call sites.

- [x] Enable lint guidance for future PRs
  - Goal: Catch regressions automatically.
  - Action: Ensure `prefer_const_constructors`/`prefer_const_literals_to_create_immutables` rules are enabled (they are in flutter_lints). Fix flagged sites incrementally.

---

## 2) 🎨 Isolate heavy paints with RepaintBoundary

- [x] Wrap map canvas
  - Goal: Prevent the whole screen from repainting when overlays change.
  - Action: Wrap `FlutterMapAdapter` in `RepaintBoundary` (already added) and keep it intact during refactors.

- [x] Wrap bottom info panel content
  - Goal: Avoid repainting the entire stack when details change.
  - Action: Wrap the single/multi info boxes in `RepaintBoundary` (already added) and keep them independent of parent AnimatedContainer where possible.

- [x] Wrap suggestions list panel
  - Goal: Limit paint cost when expanding/collapsing suggestions.
  - Action: Ensure the suggestions container/list is inside a `RepaintBoundary` (already added) to isolate its paints from the rest of the UI.

---

## 3) 💫 Smooth transitions with Animated widgets

- [x] Animate suggestions height
  - Goal: Remove jank when suggestions open/close.
  - Action: Keep `AnimatedSize` around the suggestions container (already added). Adjust `duration: 150–200ms` and curve `easeInOut` to taste.

 - [x] Polish panel content transitions
  - Goal: Cleaner swap between single-device `_InfoBox` and `_MultiSelectionInfoBox`.
  - Action: Keep `AnimatedSwitcher` and add a `transitionBuilder` (e.g., fade/slide) with keys (`'single-info'`, `'multi-info'`) to ensure smooth content changes. (already added)

- [x] Animate panel snap
  - Goal: Reduce perceptual jump between snap points.
  - Action: Tune the existing `AnimatedContainer` duration/curve to match brand feel (e.g., 180–220ms easeOut).

---

## 4) 🔍 Verify rebuilds using debug overlay

- [x] Rebuild counter badge
  - Goal: Make rebuild hotspots visible during dev.
  - Action: Toggle `MapDebugFlags.showRebuildOverlay = true` (dev only) to show a small rebuild count badge on `MapPage`. Interact and observe increments.

- [x] Performance overlay
  - Goal: Detect frames over budget quickly.
  - Action: Temporarily enable `debugShowPerformanceOverlay: true` in `MaterialApp` (debug only) to visualize frame timings. (verified in debug)

---

## 5) 🧩 Profile with Flutter DevTools

- [ ] Rebuild profiling
  - Goal: Confirm rebuild counts drop after const/isolations.
  - Action: In DevTools → Flutter Inspector → Rebuild stats, perform: typing in search, selecting devices, snapping panel, panning the map. Compare before/after.

- [ ] Frame timings & rasterization
  - Goal: Stay under 16ms for steady 60fps.
  - Action: Use the Performance tab to capture traces while rapidly toggling selections and expanding suggestions. Look for layout/paint spikes.

- [ ] Memory & image cache
  - Goal: Avoid cache bloat on low-end devices.
  - Action: Track image cache size and evictions while moving between screens; consider limiting cache and precaching hot assets (see below).

---

## 6) ⚡ Small quick wins (debounce, stable keys, color fix)

- [ ] Debounce search input
  - Goal: Avoid rebuilding on every keystroke.
  - Action: Add a 150–250ms debounce around `_query` updates (Timer-based or a small `ref.debounce(...)` helper for providers) before filtering marker/device lists.

- [ ] Stable keys for lists/items
  - Goal: Reduce list churn and preserve element state.
  - Action: Ensure suggestions `CheckboxListTile` and device list items use `key: ValueKey(deviceId)`. Markers already use stable ids.

- [x] Replace deprecated color opacity calls
  - Goal: Align with modern API and avoid precision loss.
  - Action: Replace `.withOpacity(x)` with `.withValues(alpha: x)` throughout the codebase (analyzer flagged one in `map_page.dart`).

- [ ] Precache and cap image cache
  - Goal: Reduce stutter when first showing markers and avoid memory spikes.
  - Action: Precache common marker assets in `initState()` and set `PaintingBinding.instance.imageCache.maximumSize/maximumSizeBytes` to sensible limits (e.g., 100 entries / ~50MB) in map-heavy screens.

---

## 7) 🧭 Validation checklist

- [ ] Rebuild counts decrease on: typing, selection changes, panel snap.
- [ ] Performance overlay shows no sustained over-budget frames during common interactions.
- [ ] DevTools traces show reduced layout/paint time after isolations.
- [ ] No visible flicker in suggestions expand/collapse or info panel swap.
- [ ] Memory stays stable after repeated open/close of suggestions and panel.
- [ ] Widget test remains PASS; ObjectBox tests SKIP when library is unavailable.

---

Notes
- Keep all debug/profiling toggles behind kDebugMode or static flags so tests and release builds remain unaffected.
- Tackle lints opportunistically; prefer small PRs that are safe to merge frequently.

---

## Marker Layer Optimization (notes)

- FastMarkerLayer
  - Requires flutter_map v8+. Our current project uses v7, so the API isn’t available yet.
  - If you approve upgrading flutter_map (and validating FMTC compatibility), we can switch to `FastMarkerLayer.builder` with `ValueKey(deviceId)` per marker for stable rebuilds.

- Clustering (alternative now)
  - Add `flutter_map_marker_cluster` and render clusters at low zooms, expanding automatically on tap or higher zoom.
  - This reduces per-frame marker work significantly without upgrading flutter_map.