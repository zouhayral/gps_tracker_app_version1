# AI Map Agent - Quick Reference Card

## 🚀 Quick Start (30 seconds)

```dart
// 1. Create monitor & optimizer
final perfMonitor = MapPerfMonitor();
final aiOptimizer = AiMapOptimizer(
  monitor: perfMonitor,
  onConfigChange: (config) => prefetchManager.updateAiConfig(config),
);

// 2. Start auto-optimization
aiOptimizer.startAutoOptimization();

// 3. Track map events
FlutterMap(
  options: MapOptions(
    onMapEvent: (event) {
      if (event is MapEventMoveStart) perfMonitor.onZoomStart(zoom);
      if (event is MapEventMoveEnd) perfMonitor.onZoomEnd(zoom);
    },
  ),
)

// Done! AI is now monitoring and optimizing your map.
```

## 📊 Key Metrics

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| Health Score | 80-100 | 60-80 | <60 |
| Zoom Duration | <300ms | 300-500ms | >500ms |
| Frame Drop Rate | <5% | 5-10% | >10% |
| Marker Rebuild | <50ms | 50-100ms | >100ms |
| Tile Load | <150ms | 150-200ms | >200ms |
| Memory Usage | <80MB | 80-100MB | >100MB |

## 🤖 Auto-Optimizations

| Issue Detected | AI Action | Result |
|----------------|-----------|--------|
| Slow zoom (>500ms) | Enable 300ms debounce | 40-60% faster |
| Marker rebuild >100ms | Enable bitmap cache | 70-80% faster |
| Frames dropped >5% | Switch to compact markers | Restore 60fps |
| Tile load >200ms | Reduce batch size | 30-40% faster |
| Memory >100MB | Shrink caches 30% | 20-30% reduction |
| Frequent stutters | Disable markers while zooming | Smooth zoom |

## 🔧 Manual Controls

```dart
// Get performance report
final report = perfMonitor.getPerformanceReport();
print('Health: ${report.healthScore}/100');

// Get recommendations
final recs = aiOptimizer.getRecommendations();
for (final rec in recs) {
  print('${rec.severity}: ${rec.message}');
  if (!rec.autoApply) {
    aiOptimizer.applyRecommendation(rec); // Manual apply
  }
}

// View history
final history = aiOptimizer.getHistory();
for (final action in history) {
  print('${action.timestamp}: ${action.description}');
}

// Reset metrics
perfMonitor.reset();
```

## 🐛 Debug Panel (Copy-Paste)

```dart
ListenableBuilder(
  listenable: perfMonitor,
  builder: (context, _) {
    final report = perfMonitor.getPerformanceReport();
    final recs = aiOptimizer.getRecommendations();
    
    return Card(
      child: Column(
        children: [
          Text('Health: ${report.healthScore}/100', 
            style: TextStyle(
              color: report.healthScore > 80 ? Colors.green :
                     report.healthScore > 60 ? Colors.orange :
                     Colors.red,
            ),
          ),
          Text('Zoom: ${report.avgZoomDuration}ms'),
          Text('Frames: ${report.droppedFrames} dropped'),
          Text('Rebuilds: ${report.avgMarkerRebuild}ms'),
          
          ...recs.map((r) => ListTile(
            title: Text(r.message),
            subtitle: Text(r.expectedImprovement),
            trailing: r.autoApply 
              ? Chip(label: Text('AUTO'))
              : TextButton(
                  child: Text('Apply'),
                  onPressed: () => aiOptimizer.applyRecommendation(r),
                ),
          )),
        ],
      ),
    );
  },
)
```

## 📞 Telemetry Tracking Points

### Required (Minimum)
```dart
// Zoom gestures
perfMonitor.onZoomStart(currentZoom);
perfMonitor.onZoomEnd(newZoom);
```

### Recommended (Better AI)
```dart
// Tile loads
perfMonitor.onTileLoaded(Duration(milliseconds: 150));

// Widget rebuilds
perfMonitor.onRebuild('markers', Duration(milliseconds: 45));
perfMonitor.onRebuild('tiles', Duration(milliseconds: 20));
```

### Optional (Advanced)
```dart
// Frame times
perfMonitor.onFrame(Duration(milliseconds: 18));

// Memory snapshots
perfMonitor.onMemorySnapshot(75.5); // MB
```

## 🎯 Health Score Breakdown

```
100 points total:

- Zoom performance:        40 points max
  < 300ms = 40 pts
  300-500ms = 20 pts
  > 500ms = 0 pts

- Frame smoothness:        30 points max
  < 5% drops = 30 pts
  5-10% drops = 15 pts
  > 10% drops = 0 pts

- Rebuild efficiency:      20 points max
  < 50ms = 20 pts
  50-100ms = 10 pts
  > 100ms = 0 pts

- Bottleneck count:        10 points max
  < 5 = 10 pts
  5-10 = 5 pts
  > 10 = 0 pts
```

## 🔍 Troubleshooting

### "Health score stuck at low value"
```dart
// Check what's bottlenecking
final report = perfMonitor.getPerformanceReport();
print(report.bottlenecks); // e.g. {zoom_slow: 15, frame_drop: 8}

// Get specific recommendations
final recs = aiOptimizer.getRecommendations();
recs.forEach((r) => print('Fix: ${r.message}'));
```

### "Optimizations not applying"
```dart
// Verify config callback is set
final optimizer = AiMapOptimizer(
  monitor: perfMonitor,
  onConfigChange: (config) {
    print('Config updated: ${config.toJson()}'); // Should print
    prefetchManager.updateAiConfig(config);
  },
);

// Check if auto-optimization is running
optimizer.startAutoOptimization(); // Must call this!
```

### "Too many recommendations"
```dart
// Filter by severity
final critical = aiOptimizer.getRecommendations()
    .where((r) => r.severity == RecommendationSeverity.critical);

// Or stop auto-optimization and apply manually
aiOptimizer.stopAutoOptimization();
```

## 📦 File Locations

```
lib/core/map/
├── map_perf_monitor.dart         # Telemetry collector
├── ai_map_optimizer.dart         # AI optimization engine
└── fleet_map_prefetch.dart       # Integration point

docs/
├── AI_MAP_AGENT_GUIDE.md         # Full integration guide
├── AI_MAP_AGENT_SUMMARY.md       # Implementation summary
└── AI_MAP_AGENT_QUICK_REF.md     # This file
```

## 🎓 Key Terms

| Term | Definition |
|------|------------|
| **Telemetry** | Performance data collected in real-time |
| **Bottleneck** | Performance issue limiting speed |
| **Health Score** | 0-100 rating of map performance |
| **Auto-Optimization** | AI applies fixes automatically |
| **Recommendation** | Suggested optimization with expected impact |
| **Debounce** | Delay before action to reduce frequency |
| **Prefetch** | Load data before it's needed |
| **Adaptive** | Changes behavior based on conditions |

## ⚡ Performance Targets

```
Map Load:      < 600ms   (with snapshot cache)
Zoom Gesture:  < 300ms   (smooth animation)
Frame Time:    < 16ms    (60fps = 16.67ms budget)
Marker Rebuild: < 50ms   (fast enough to avoid jank)
Tile Load:     < 150ms   (instant feel)
Memory:        < 80MB    (leaves room for app)
```

## 🎯 When to Use

✅ **Use AI Agent when:**
- You have 10+ markers on screen
- Users frequently zoom/pan
- You want adaptive performance
- Testing on various devices
- Need automatic optimization

❌ **Skip AI Agent when:**
- Static map (no interaction)
- <5 markers total
- Performance already perfect
- Testing in isolation
- Need deterministic behavior

## 📱 Device Adaptation

The AI automatically adapts to device capabilities:

| Device Type | Typical Adjustments |
|-------------|---------------------|
| High-end (iPhone 15, Pixel 8) | Full markers, no debounce, large caches |
| Mid-range (iPhone 12, Pixel 6) | Mixed markers, 150ms debounce, medium caches |
| Low-end (older devices) | Compact markers, 300ms debounce, small caches |

## 🔄 Update Cycle

```
Every 10 seconds:
  ↓
Collect telemetry snapshot
  ↓
Calculate health score
  ↓
Detect bottlenecks
  ↓
Generate recommendations
  ↓
Auto-apply safe optimizations
  ↓
Notify listeners
  ↓
Repeat...
```

## 🆘 Support

Issues? Check:
1. **Console logs** - Look for `[AI_AGENT]` and `[AI_OPTIMIZER]` prefixes
2. **Health score** - <60 means critical issues
3. **Recommendations** - AI will tell you what's wrong
4. **History** - See what was already tried

## 🎉 Success!

If you see:
- Health score 80+
- Zoom duration <300ms
- Frame drop rate <5%
- Auto-optimizations being applied

**Your AI agent is working perfectly!** 🚀

---

**Quick Links:**
- Full Guide: `AI_MAP_AGENT_GUIDE.md`
- Implementation: `lib/core/map/map_perf_monitor.dart`
- Examples: `AI_MAP_AGENT_GUIDE.md` (sections 5-6)
