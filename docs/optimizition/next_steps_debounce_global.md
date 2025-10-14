# Global Debounce/Throttle Plan

## Goal
Prevent UI jank during frequent search or map updates by applying Debouncer and Throttler consistently across the app.

## Actions Taken
- Added core utilities: Debouncer, Throttler (lib/core/utils/timing.dart)
- Map Page: Debounced search input (250ms), throttled camera updates (300ms)
- Dashboard: Debounced device search input (250ms)
- Map Adapter: Throttled move/fit operations centrally to avoid rapid camera updates from any path

## Validation
- Flutter DevTools → Inspector → Track Rebuilds: verify reduced rebuilds when typing or selecting devices
- Flutter DevTools → Performance: record while typing and focusing devices; confirm frame times <16ms and fewer camera updates
- Manual: type quickly in dashboard search and map search; pan/select devices repeatedly; transitions remain smooth

## Checklist
- [x] Debouncer in map_page.dart
- [x] Debouncer in dashboard_page.dart
- [x] Throttler in flutter_map_adapter.dart (centralized camera throttling)
- [ ] Validate rebuild count drop (<10 rebuilds/second)
