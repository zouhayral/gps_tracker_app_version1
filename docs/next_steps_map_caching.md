# Map Caching & Assets

Goal: Improve map rendering performance, reduce frame stutter, and enhance offline usability by reusing marker icons, limiting cache memory, and precaching key assets.

## Actions Taken
- Enabled flutter_map_tile_caching (FMTC) at startup and configured TileLayer to use FMTC provider when available.
- Limited global ImageCache to ~50 MB and 200 entries to reduce memory pressure.
- Added MarkerAssets helper to preload and reuse marker icons across rebuilds.
- Precached common marker images after first frame in AppRoot.
- Switched marker rendering to use preloaded raster images; added vector IconData overlays for status.

## Validation Checklist
- [x] FMTC tile caching enabled
- [x] Marker icons preloaded and reused
- [x] Vector icons integrated for statuses (IconData fallback)
- [x] Image cache size limited to 50 MB
- [x] Common markers precached

## Testing Method
1. Run the app and open Flutter DevTools → Memory. Verify ImageCache stabilizes and does not grow without bounds.
2. Toggle offline mode and pan/zoom the map. Tiles and markers should still render from cache where available.
3. Profile a first scroll across markers; frame time should improve (target < 10 ms on average vs previous > 16 ms spikes).

## Notes
- FMTC is used via FMTCTileProvider on the FlutterMap TileLayer when enabled.
- To troubleshoot FMTC, set kForceDisableFMTC to true in FlutterMapAdapter.
- If SVG assets are introduced later, prefer flutter_svg for crisp scaling; for now, IconData provides a vector fallback.
