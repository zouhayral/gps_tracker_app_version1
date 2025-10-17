void _onMarkerTap(String id) {
  final n = int.tryParse(id);
  if (n == null) return;
  setState(() {
  // This file previously contained a stray helper function that was
  // accidentally written as a top-level file (it caused undefined
  // identifier errors in static analysis). The implementation has
  // been intentionally removed. If you need a helper to handle
  // marker taps, please add it to the MapPage state class where
  // `_selectedIds`, `setState`, and `_scheduleMarkersUpdate` are
  // defined.

  // Intentionally empty placeholder to keep repository clean.
  });
  // Trigger a markers recompute quickly (course icon/selection ring)
  _scheduleMarkersUpdate();
}