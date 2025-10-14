# Next Steps: Animated Transitions

A focused plan to replace heavy rebuilds with lightweight, smooth animations.

---

## Goal and Rationale
- Improve perceived performance and reduce frame jank by animating size/opacity instead of rebuilding large trees.
- Keep repaints localized using RepaintBoundary while UI elements expand/collapse or swap.

---

## Action Steps
- Wrap expanding suggestions dropdown in AnimatedSize (200ms, easeInOut). Keep the list inside a RepaintBoundary.
- Wrap info panel content (single vs. multi) in AnimatedSwitcher with a fade+slight slide transition (220ms, easeInOut). Use ValueKey('single-info')/ValueKey('multi-info').
- Keep panel snap height changes in an AnimatedContainer (200ms, easeOut).
- Use stable keys for list items (ValueKey(deviceId)) to avoid flicker/state loss.
- Ensure RepaintBoundary stays around map canvas and info panel content.

---

## Checklist
- [x] AnimatedSize for suggestions dropdown
- [x] AnimatedSwitcher for panel content swap with transitionBuilder
- [x] AnimatedContainer for panel snap
- [x] Stable ValueKeys on panel children and list items
- [x] RepaintBoundary around map and panel content

---

## Validation Criteria
- Suggestions expand/collapse smoothly with no layout jumps
- Info panel switches between single/multi smoothly with fade/slide
- No flicker while panning the map or changing selection
- Repaint regions remain localized (verify with Performance Overlay)
- DevTools shows reduced rebuild counts and frame times under 16ms during typical interactions

---

## How to Validate (DevTools)
- Open Flutter DevTools → Flutter Inspector → Track Rebuilds; interact with search, selection, and panel snaps.
- Open Performance tab → Record while toggling suggestions and switching panel content; confirm frame budget met.
