
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/core/utils/timing.dart';
import 'package:flutter/foundation.dart';
import 'package:my_app_gps/services/fmtc_initializer.dart';
import 'package:my_app_gps/core/map/fps_monitor.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:my_app_gps/core/map/marker_cache.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/core/map_adapter.dart';
import 'package:my_app_gps/features/map/data/granular_providers.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/features/map/data/positions_last_known_provider.dart';
import 'package:my_app_gps/features/map/data/positions_live_provider.dart';
import 'package:my_app_gps/features/map/view/flutter_map_adapter.dart';
import 'package:my_app_gps/services/websocket_manager.dart';

// Clean rebuilt MapPage implementation
// Features:
//  - Gated search bar (single tap show suggestions, double tap or keyboard icon to edit)
//  - Tri‑state All devices selection (all / some / none)
//  - Live positions preferred over stored device lat/lon
//  - Multi‑snap bottom panel (stops: 5%, 30%, 50%, 80%) with drag velocity ±250
//  - Deep link preselection focus (preselectedIds)
//  - Single, duplicate‑free implementation (previous corruption removed)
// FMTC tile provider singleton via Riverpod

final _tileProviderProvider = Provider<TileProvider>((ref) {
  // Only create once per app session. The FMTC store should be warmed up
  // by `FMTCInitializer.warmup()` called from the MapPage lifecycle before
  // this provider is read to avoid synchronous initialization during build.
  return FMTCTileProvider(stores: const {'main': null});
});

// Marker cache provider
final markerCacheProvider = Provider<MarkerCache>((ref) => MarkerCache());

// Debounced positions helper
Map<int, Position> useDebouncedPositions(AsyncValue<Map<int, Position>> positionsAsync, Duration debounce) {
  // Simple debounce: returns latest positions after delay
  var latest = <int, Position>{};
  positionsAsync.when(
    data: (map) {
      Future.delayed(debounce, () => latest = Map<int, Position>.unmodifiable(map));
    },
    loading: () {},
    error: (_, __) {},
  );
  return latest;
}

/// Debug toggles for map page (safe defaults: all off)
class MapDebugFlags {
  static bool showRebuildOverlay = false; // enable to show rebuild counters overlay
}

// Simple rebuild badge for profiling; increments an internal counter each build.
class _RebuildBadge extends StatefulWidget {
  const _RebuildBadge({required this.label});
  final String label;
  @override
  State<_RebuildBadge> createState() => _RebuildBadgeState();
}

class _RebuildBadgeState extends State<_RebuildBadge> {
  int _count = 0;
  @override
  Widget build(BuildContext context) {
    _count++;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '${widget.label}: $_count',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key, this.preselectedIds});
  final Set<int>? preselectedIds;
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  // Selection
  final Set<int> _selectedIds = <int>{};

  // Search / suggestions gating
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  bool _editing = false; // when true TextField accepts input
  bool _showSuggestions = false;
  final _searchDebouncer = Debouncer(const Duration(milliseconds: 250));

  // Map
  final _mapKey = GlobalKey<FlutterMapAdapterState>();
  bool _didAutoFocus = false;
  Timer? _preselectSnackTimer;
  // Debounce helper for live positions
  Timer? _positionsDebounceTimer;
  Map<int, Position> _debouncedPositions = const <int, Position>{};
  // Throttle camera fit operations to avoid rapid repeated moves (only for bounds fitting).
  final _fitThrottler = Throttler(const Duration(milliseconds: 300));
  // Track last selected device to detect changes
  int? _lastSelectedSingleDevice;

  // Bottom panel snaps
  final List<double> _panelStops = const [0.05, 0.30, 0.50, 0.80];
  int _panelIndex = 1; // start at 30%

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));

    // Eagerly initialize position providers to ensure WebSocket connects
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Initialize both providers (starts WebSocket + fetches from API)
      ref
        ..read(positionsLiveProvider)
        ..read(positionsLastKnownProvider);
    });

    // Warm up FMTC asynchronously - do not await here to avoid blocking initState
    FMTCInitializer.warmup().then((_) {
      debugPrint('[FMTC] warmup finished');
    }).catchError((Object e, StackTrace? st) {
      debugPrint('[FMTC] warmup error: $e');
    });

    // Debounced positions: listen to the live stream and update a cached map
    // on a timer to avoid rebuilding the entire map on every socket tick.
    _positionsDebounceTimer = null;
    _debouncedPositions = const <int, Position>{};
    ref.listen<AsyncValue<Map<int, Position>>>(positionsLiveProvider, (prev, next) {
      final data = next.asData?.value;
      _positionsDebounceTimer?.cancel();
      if (data == null) {
        // Keep previous debounced positions if stream yields null/loading
        return;
      }
      _positionsDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        setState(() {
          _debouncedPositions = Map<int, Position>.unmodifiable(data);
        });
      });
    });

    if (widget.preselectedIds != null && widget.preselectedIds!.isNotEmpty) {
      _selectedIds.addAll(widget.preselectedIds!);
      // Snackbar reminder if not focused after delay
      _preselectSnackTimer = Timer(const Duration(seconds: 6), () {
        if (!mounted) return;
        if (!_didAutoFocus && widget.preselectedIds!.isNotEmpty) {
          final ids = widget.preselectedIds!;
          final sample = ids.take(5).join(', ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Devices not located yet: $sample${ids.length > 5 ? ' +${ids.length - 5}' : ''}',
              ),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () => setState(() {}),
              ),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _preselectSnackTimer?.cancel();
    _searchDebouncer.cancel();
    _positionsDebounceTimer?.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------
  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  bool _valid(double? lat, double? lon) =>
      lat != null &&
      lon != null &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  void _onMarkerTap(String id) {
    final n = int.tryParse(id);
    if (n == null) return;

    // Optimized: Get position data BEFORE setState to trigger immediate camera move
    final position = ref.read(positionByDeviceProvider(n));
    final hasValidPos = position != null &&
        _valid(position.latitude, position.longitude);

    setState(() {
      if (_selectedIds.contains(n)) {
        _selectedIds.remove(n);
      } else {
        _selectedIds.add(n);
        // Trigger immediate camera move if this is now the only selected device
        if (_selectedIds.length == 1 && hasValidPos) {
          // Move camera synchronously, no delays
          _mapKey.currentState?.moveTo(
            LatLng(position.latitude, position.longitude),
          );
        }
      }
    });
  }

  void _onMapTap() {
    var changed = false;
    if (_selectedIds.isNotEmpty) {
      _selectedIds.clear();
      changed = true;
    }
    if (!_editing && _showSuggestions) {
      _showSuggestions = false;
      changed = true;
    }
    if (changed) setState(() {});
  }

  void _focusSelected() =>
      setState(() {}); // triggers rebuild to adjust camera fit

  String _deviceStatus(Map<String, dynamic>? device, Position? pos) {
    final raw = device?['status']?.toString().toLowerCase();
    if (raw == 'online' || raw == 'offline' || raw == 'unknown') return raw!;
    DateTime? last;
    final lu = device?['lastUpdateDt'];
    if (lu is DateTime) last = lu.toUtc();
    if (pos != null) {
      final pt = pos.deviceTime.toUtc();
      if (last == null || pt.isAfter(last)) last = pt;
    }
    if (last == null) return 'unknown';
    final age = DateTime.now().toUtc().difference(last);
    if (age < const Duration(minutes: 5)) return 'online';
    if (age < const Duration(hours: 12)) return 'offline';
    return 'unknown';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'online':
        return const Color(0xFFA6CD27);
      case 'offline':
        return const Color(0xFFFF383C);
      default:
        return const Color(0xFF49454F);
    }
  }

  String _formatRelativeAge(DateTime? dt) {
    if (dt == null) return 'n/a';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    final d = diff.inDays;
    if (d < 7) return '${d}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    // Watch entire devices list only once; consider splitting into smaller providers later
    final devicesAsync = ref.watch(devicesNotifierProvider);
  // Only watch the latest positions map value via ref.listen in initState to avoid rebuilds
  ref.watch(positionsLiveProvider); // ensure provider is active
    // Also watch last-known fallback to render markers when live map is empty
    final lastKnownMap = ref.watch(
      positionsLastKnownProvider.select((async) => async.asData?.value),
    );
  // Use marker cache and debounced positions (debounced map updated via ref.listen)
  final markerCache = ref.watch(markerCacheProvider);
  final debouncedPositions = _debouncedPositions;
    return Scaffold(
      body: SafeArea(
        child: devicesAsync.when(
          data: (devices) {
            // Use debounced positions for smoother updates
            final positions = debouncedPositions.isNotEmpty
                ? debouncedPositions
                : (lastKnownMap ?? const <int, Position>{});
            final q = _query.trim().toLowerCase();
            // Use marker cache to memoize marker creation
            final markers = markerCache.getMarkers(
              positions,
              devices,
              _selectedIds,
              q,
            );

            // If exactly one device is selected, center to its position IMMEDIATELY
            if (_selectedIds.length == 1) {
              final sid = _selectedIds.first;

              // Try to get position from provider (live or last-known)
              final merged = ref.watch(positionByDeviceProvider(sid));
              double? targetLat;
              double? targetLon;

              if (merged != null && _valid(merged.latitude, merged.longitude)) {
                targetLat = merged.latitude;
                targetLon = merged.longitude;
              } else {
                // Fallback to device's stored lat/lon if no position data
                final device = ref.read(deviceByIdProvider(sid));
                final lat = _asDouble(device?['latitude']);
                final lon = _asDouble(device?['longitude']);
                if (_valid(lat, lon)) {
                  targetLat = lat;
                  targetLon = lon;
                }
              }

              // Center camera if we have valid coordinates
              if (targetLat != null && targetLon != null) {
                final selectionChanged = _lastSelectedSingleDevice != sid;
                if (selectionChanged) {
                  _lastSelectedSingleDevice = sid;
                  // Immediate move without throttling
                  // This ensures <100ms response time
                  final lat = targetLat;
                  final lon = targetLon;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _mapKey.currentState?.moveTo(
                      LatLng(lat, lon),
                    );
                  });
                }
              } else {
                // Device has no location data - show a message
                final selectionChanged = _lastSelectedSingleDevice != sid;
                if (selectionChanged) {
                  _lastSelectedSingleDevice = sid;
                  // Show snackbar to inform user
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    final device = ref.read(deviceByIdProvider(sid));
                    final deviceName = device?['name'] ?? 'Device $sid';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '$deviceName has no location data yet',
                        ),
                        duration: const Duration(seconds: 3),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  });
                }
              }
            } else {
              _lastSelectedSingleDevice = null;
            }

            // Camera fit
            MapCameraFit fit;
            final selectedMarkers = _selectedIds.isEmpty
                ? <MapMarkerData>[]
                : markers
                      .where(
                        (m) => _selectedIds.contains(int.tryParse(m.id) ?? -1),
                      )
                      .toList();
            final target = selectedMarkers.isNotEmpty
                ? selectedMarkers
                : markers;
            if (target.isEmpty) {
              fit = const MapCameraFit(center: LatLng(0, 0));
            } else if (target.length == 1) {
              fit = MapCameraFit(center: target.first.position);
            } else {
              fit = MapCameraFit(
                boundsPoints: [for (final m in target) m.position],
              );
            }

            // Deep link autofocus one-time
            if (!_didAutoFocus &&
                widget.preselectedIds != null &&
                widget.preselectedIds!.isNotEmpty) {
              final hasAny = markers.any(
                (m) =>
                    widget.preselectedIds!.contains(int.tryParse(m.id) ?? -1),
              );
              if (hasAny) {
                _didAutoFocus = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (target.isEmpty) return;
                  _fitThrottler.run(() {
                    if (target.length == 1) {
                      _mapKey.currentState?.moveTo(target.first.position);
                    } else {
                      setState(() {}); // trigger rebuild for bounds fit
                    }
                  });
                });
              }
            }

            // Suggestions list
            final suggestions = _showSuggestions
                ? [
                    if (_query.isEmpty || 'all devices'.contains(q))
                      {'__all__': true, 'name': 'All devices'},
                    ...devices.where((d) {
                      final n = d['name']?.toString().toLowerCase() ?? '';
                      return _query.isEmpty || n.contains(q);
                    }),
                  ]
                : const <Map<String, dynamic>>[];

            return Stack(
              children: [
                RepaintBoundary(
                  child: Stack(
                    children: [
                      FlutterMapAdapter(
                        key: _mapKey,
                        markers: markers,
                        cameraFit: fit,
                        onMarkerTap: _onMarkerTap,
                        onMapTap: _onMapTap,
                        tileProvider: ref.watch(_tileProviderProvider),
                      ),
                      if (kDebugMode) const FpsMonitor(),
                    ],
                  ),
                ),
                if (MapDebugFlags.showRebuildOverlay)
                  const Positioned(
                    top: 56,
                    left: 16,
                    child: _RebuildBadge(label: 'MapPage'),
                  ),
                // Search + suggestions
                Positioned(
                  top: 12,
                  left: 16,
                  right: 88,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SearchBar(
                        controller: _searchCtrl,
                        focusNode: _focusNode,
                        editing: _editing,
                        suggestionsVisible: _showSuggestions,
                        onChanged: (v) => _searchDebouncer.run(
                          () => setState(() => _query = v),
                        ),
                        onClear: () {
                          _searchCtrl.clear();
                          _searchDebouncer.run(() => setState(() => _query = ''));
                        },
                        onRequestEdit: () {
                          setState(() {
                            _editing = true;
                            _showSuggestions = true;
                          });
                          FocusScope.of(context).requestFocus(_focusNode);
                        },
                        onCloseEditing: () {
                          setState(() => _editing = false);
                          _focusNode.unfocus();
                        },
                        onSingleTap: () {
                          if (!_showSuggestions) {
                            setState(() => _showSuggestions = true);
                          }
                        },
                        onDoubleTap: () {
                          if (!_editing) {
                            setState(() {
                              _editing = true;
                              _showSuggestions = true;
                            });
                            FocusScope.of(context).requestFocus(_focusNode);
                          }
                        },
                        onToggleSuggestions: () => setState(
                          () => _showSuggestions = !_showSuggestions,
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: suggestions.isNotEmpty
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 5),
                                  RepaintBoundary(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                          bottom: Radius.circular(22),
                                        ),
                                        border:
                                            Border.all(color: Colors.black12),
                                      ),
                                      constraints: const BoxConstraints(
                                        maxHeight: 260,
                                      ),
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: suggestions.length,
                                        itemBuilder: (ctx, i) {
                                          final d = suggestions[i];
                                          if (d['__all__'] == true) {
                                            final total = devices.length;
                                            final allSelected = _selectedIds.length == total && total > 0;
                                            final someSelected = _selectedIds.isNotEmpty && !allSelected;
                                            return CheckboxListTile(
                                              key: const ValueKey('__all__'),
                                              dense: true,
                                              tristate: true,
                                              controlAffinity:
                                                  ListTileControlAffinity
                                                      .leading,
                                              title: Text('All devices ($total)'),
                                              value: allSelected
                                                  ? true
                                                  : (someSelected ? null : false),
                                              onChanged: (_) {
                                                setState(() {
                                                  if (allSelected) {
                                                    _selectedIds.clear();
                                                  } else {
                                                    _selectedIds
                                                      ..clear()
                                                      ..addAll(
                                                        devices
                                                            .map((e) => e['id'])
                                                            .whereType<int>(),
                                                      );
                                                  }
                                                });
                                              },
                                            );
                                          }
                      final name = d['name']?.toString() ?? 'Device';
                                          final idRaw = d['id'];
                                          final id = (idRaw is int)
                                              ? idRaw
                                              : int.tryParse(idRaw?.toString() ?? '');
                                          final pos = id == null ? null : positions[id];
                                          final lat = pos?.latitude ?? _asDouble(d['latitude']);
                                          final lon = pos?.longitude ?? _asDouble(d['longitude']);
                                          final hasCoords = _valid(lat, lon);
                                          final selected = id != null && _selectedIds.contains(id);
                                          DateTime? last;
                                          final devLast = d['lastUpdateDt'];
                                          if (devLast is DateTime) last = devLast.toLocal();
                                          final posTime = pos?.deviceTime.toLocal();
                                          if (posTime != null && (last == null || posTime.isAfter(last))) {
                                            last = posTime;
                                          }
                                          final subtitle = last == null
                                              ? 'No update yet'
                                              : 'Updated ${_formatRelativeAge(last)}';
                                          return CheckboxListTile(
                                            key: ValueKey('sugg_${id ?? name}'),
                                            dense: true,
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            value: selected,
                                            title: Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(subtitle),
                                            onChanged: id == null
                                                ? null
                                                : (val) {
                                                    setState(() {
                                                      if (val ?? false) {
                                                        _selectedIds.add(id);
                                                      } else {
                                                        _selectedIds.remove(id);
                                                      }
                                                    });
                                                    // Immediately center on selected device
                                                    if (hasCoords && (val ?? false)) {
                                                      // Direct synchronous update for instant response
                                                      _mapKey.currentState?.moveTo(
                                                        LatLng(lat!, lon!),
                                                      );
                                                    }
                                                  },
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                // Map action buttons
                Positioned(
                  top: 12,
                  right: 16,
                  child: Column(
                    children: [
                      // Connection status indicator
                      _ConnectionStatusBadge(
                        connectionStatus: ref.watch(webSocketProvider.select((s) => s.status)),
                        positionsCount: positions.length,
                      ),
                      const SizedBox(height: 10),
                      _ActionButton(
                        icon: Icons.refresh,
                        tooltip: 'Refresh data',
                        onTap: () async {
                          // 1) Refresh static data from Traccar (devices list)
                          try {
                            await ref
                                .read(devicesNotifierProvider.notifier)
                                .refresh();
                          } catch (_) {
                            // ignore device refresh errors here; UI will show via provider state
                          }
                          // 2) Restart positions stream (re-subscribe to socket)
                          ref.invalidate(positionsLiveProvider);
                        },
                      ),
                      const SizedBox(height: 10),
                      _ActionButton(
                        icon: Icons.center_focus_strong,
                        tooltip: _selectedIds.isNotEmpty
                            ? 'Focus selected'
                            : 'Select a device first',
                        onTap: _selectedIds.isNotEmpty ? _focusSelected : null,
                        disabled: _selectedIds.isEmpty,
                      ),
                    ],
                  ),
                ),
                // Bottom multi-snap panel
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _selectedIds.isEmpty
                        ? const SizedBox.shrink()
                        : LayoutBuilder(
                            key: ValueKey(_selectedIds.hashCode ^ _panelIndex),
                            builder: (ctx, _) {
                              final screenH = MediaQuery.of(
                                context,
                              ).size.height;
                              final height =
                                  (screenH * _panelStops[_panelIndex]).clamp(
                                    90.0,
                                    screenH * 0.9,
                                  );
                              return GestureDetector(
                                onVerticalDragEnd: (details) {
                                  final v = details.primaryVelocity ?? 0;
                                  if (v > 250) {
                                    setState(
                                      () => _panelIndex = (_panelIndex - 1)
                                          .clamp(0, _panelStops.length - 1),
                                    );
                                  } else if (v < -250) {
                                    setState(
                                      () => _panelIndex = (_panelIndex + 1)
                                          .clamp(0, _panelStops.length - 1),
                                    );
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                  height: height,
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    10,
                                    16,
                                    16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(24),
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFFA6CD27),
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      InkWell(
                                        onTap: () => setState(
                                          () => _panelIndex =
                                              (_panelIndex + 1) %
                                              _panelStops.length,
                                        ),
                                        borderRadius: BorderRadius.circular(40),
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                            bottom: 8,
                                          ),
                                          child: Container(
                                            width: 56,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: Colors.grey[400],
                                              borderRadius:
                                                  BorderRadius.circular(40),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: ClipRect(
                                          child: SingleChildScrollView(
                                            padding: EdgeInsets.zero,
                                            physics:
                                                const BouncingScrollPhysics(),
                                            child: RepaintBoundary(
                                              child: AnimatedSwitcher(
                                                duration: const Duration(milliseconds: 220),
                                                switchInCurve: Curves.easeInOut,
                                                switchOutCurve: Curves.easeInOut,
                                                transitionBuilder: (child, animation) {
                                                  final slide = Tween<Offset>(
                                                    begin: const Offset(0, 0.02),
                                                    end: Offset.zero,
                                                  ).animate(animation);
                                                  return FadeTransition(
                                                    opacity: animation,
                                                    child: SlideTransition(position: slide, child: child),
                                                  );
                                                },
                                                child: _selectedIds.length == 1
                                                  ? _InfoBox(
                                                    key: const ValueKey(
                                                      'single-info',
                                                    ),
                                                    deviceId:
                                                        _selectedIds.first,
                                                    devices: devices,
                                                    position: ref.watch(
                                                      positionByDeviceProvider(
                                                        _selectedIds.first,
                                                      ),
                                                    ),
                                                    statusResolver:
                                                        _deviceStatus,
                                                    statusColorBuilder:
                                                        _statusColor,
                                                    onClose: () => setState(
                                                      _selectedIds.clear,
                                                    ),
                                                    onFocus: _focusSelected,
                                                  )
                                                  : _MultiSelectionInfoBox(
                                                    key: const ValueKey(
                                                      'multi-info',
                                                    ),
                                                    selectedIds: _selectedIds,
                                                    devices: devices,
                                                    positions: positions,
                                                    statusResolver:
                                                        _deviceStatus,
                                                    statusColorBuilder:
                                                        _statusColor,
                                                    onClear: () => setState(
                                                      _selectedIds.clear,
                                                    ),
                                                    onFocus: _focusSelected,
                                                  ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_panelIndex == 0)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: Text(
                                            'Tap or swipe up for more',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to load devices for map: $e'),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- UI COMPONENTS ----------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.focusNode,
    required this.editing,
    required this.onRequestEdit,
    required this.onCloseEditing,
    required this.onSingleTap,
    required this.onDoubleTap,
    required this.onToggleSuggestions,
    required this.suggestionsVisible,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final FocusNode focusNode;
  final bool editing;
  final VoidCallback onRequestEdit;
  final VoidCallback onCloseEditing;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onToggleSuggestions;
  final bool suggestionsVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = controller.text.isNotEmpty;
    final active = editing || focusNode.hasFocus;
    final borderColor = active ? const Color(0xFFA6CD27) : Colors.black12;
    return GestureDetector(
      onTap: onSingleTap,
      onDoubleTap: onDoubleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor, width: active ? 1.5 : 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.search, color: Colors.grey[700], size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                readOnly: !editing,
                onChanged: onChanged,
                cursorColor: const Color(0xFF49454F),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search vehicle',
                  border: InputBorder.none,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onToggleSuggestions,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  suggestionsVisible ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: Colors.black54,
                ),
              ),
            ),
            if (hasText)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 20, color: Colors.black54),
                ),
              )
            else
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => editing ? onCloseEditing() : onRequestEdit(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    editing ? Icons.keyboard_hide : Icons.keyboard,
                    size: 20,
                    color: Colors.black54,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.disabled = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool disabled;
  @override
  Widget build(BuildContext context) {
  final bg = disabled ? Colors.white.withValues(alpha: 0.6) : Colors.white;
    final fg = disabled ? Colors.black26 : Colors.black87;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 4,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 22, color: fg),
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.deviceId,
    required this.devices,
    required this.position,
    required this.statusResolver,
    required this.statusColorBuilder,
    required this.onClose,
    super.key,
    this.onFocus,
  });
  final int deviceId;
  final List<Map<String, dynamic>> devices;
  final Position? position;
  final String Function(Map<String, dynamic>?, Position?) statusResolver;
  final Color Function(String) statusColorBuilder;
  final VoidCallback onClose; // currently unused but reserved for close button
  final VoidCallback? onFocus;
  @override
  Widget build(BuildContext context) {
    assert(
      debugCheckHasDirectionality(context),
      '_InfoBox requires Directionality above in the tree',
    );
    String relativeAge(DateTime? dt) {
      if (dt == null) return 'n/a';
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      final d = diff.inDays;
      if (d < 7) return '${d}d ago';
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    var name = 'Device $deviceId';
    for (final d in devices) {
      if (d['id'] == deviceId) {
        name = d['name']?.toString() ?? name;
        break;
      }
    }
    var deviceMap = const <String, dynamic>{};
    for (final d in devices) {
      if (d['id'] == deviceId) {
        deviceMap = d;
        break;
      }
    }
    final status = statusResolver(deviceMap, position);
    final statusColor = statusColorBuilder(status);
    final engineAttr = position?.attributes['ignition'];
    final engine = engineAttr is bool ? (engineAttr ? 'on' : 'off') : '_';
    final speed = position?.speed.toStringAsFixed(0) ?? '--';
    final distanceAttr =
        position?.attributes['distance'] ??
        position?.attributes['totalDistance'];
    String distance;
    if (distanceAttr is num) {
      final km = distanceAttr / 1000;
      distance = km >= 0.1 ? km.toStringAsFixed(0) : '00';
    } else {
      distance = '--';
    }
    // Try to get coordinates from position, then fallback to device data
    final String lastLocation;
    final pos = position;
    if (pos != null) {
      final posAddress = pos.address;
      if (posAddress != null && posAddress.isNotEmpty) {
        lastLocation = posAddress;
      } else {
        lastLocation = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      }
    } else {
      // Fallback to device's stored lat/lon if no position
      final devLat = deviceMap['latitude'];
      final devLon = deviceMap['longitude'];
      if (devLat != null && devLon != null) {
        lastLocation = '$devLat, $devLon (stored)';
      } else {
        lastLocation = 'No location data available';
      }
    }
    final deviceTime = position?.deviceTime.toLocal();
    final lastUpdateDt = (deviceMap['lastUpdateDt'] is DateTime)
        ? (deviceMap['lastUpdateDt'] as DateTime).toLocal()
        : deviceTime;
    final lastAge = relativeAge(lastUpdateDt);
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Engine & Movement',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: .3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _InfoLine(
                    icon: Icons.power_settings_new,
                    label: 'Engine',
                    value: engine,
                    valueColor: engine == 'on' ? statusColor : null,
                  ),
                  _InfoLine(
                    icon: Icons.speed,
                    label: 'Speed',
                    value: speed == '--' ? '-- km/h' : '$speed km/h',
                  ),
                  _InfoLine(
                    icon: Icons.route,
                    label: 'Distance',
                    value: distance == '--' ? '-- km' : '$distance km',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Last Location',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: .3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _InfoLine(
                    icon: Icons.place_outlined,
                    label: 'Coordinates',
                    value: lastLocation,
                    valueColor: lastLocation == 'No location data available'
                        ? Colors.orange
                        : null,
                  ),
                  _InfoLine(
                    icon: Icons.update,
                    label: 'Updated',
                    value: lastAge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiSelectionInfoBox extends StatelessWidget {
  const _MultiSelectionInfoBox({
    required this.selectedIds,
    required this.devices,
    required this.positions,
    required this.statusResolver,
    required this.statusColorBuilder,
    required this.onClear,
    super.key,
    this.onFocus,
  });
  final Set<int> selectedIds;
  final List<Map<String, dynamic>> devices;
  final Map<int, Position> positions;
  final String Function(Map<String, dynamic>?, Position?) statusResolver;
  final Color Function(String) statusColorBuilder;
  final VoidCallback onClear;
  final VoidCallback? onFocus;
  @override
  Widget build(BuildContext context) {
    assert(
      debugCheckHasDirectionality(context),
      '_MultiSelectionInfoBox requires Directionality above in the tree',
    );
    final selectedDevices = devices
        .whereType<Map<String, dynamic>>()
        .where((d) => selectedIds.contains(d['id']))
        .toList();
    var online = 0;
    var offline = 0;
    var unknown = 0;
    for (final d in selectedDevices) {
      final s = statusResolver(d, positions[d['id']]);
      switch (s) {
        case 'online':
          online++;
        case 'offline':
          offline++;
        default:
          unknown++;
      }
    }
    final total = selectedDevices.length;
    final onlinePct = total == 0 ? 0 : (online / total * 100).round();
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '$total devices selected',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _StatusStat(
                  label: 'Online',
                  count: online,
                  color: statusColorBuilder('online'),
                ),
                _StatusStat(
                  label: 'Offline',
                  count: offline,
                  color: statusColorBuilder('offline'),
                ),
                _StatusStat(
                  label: 'Unknown',
                  count: unknown,
                  color: statusColorBuilder('unknown'),
                ),
                Text(
                  'Online: $onlinePct%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (selectedDevices.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final d in selectedDevices.take(5))
                    _InfoLine(
                      icon: Icons.device_hub,
                      label: d['name']?.toString() ?? 'Device',
                      value: statusResolver(d, positions[d['id']]),
                      valueColor: statusColorBuilder(
                        statusResolver(d, positions[d['id']]),
                      ),
                    ),
                  if (selectedDevices.length > 5)
                    Text(
                      '+ ${selectedDevices.length - 5} more...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodySmall;
    final styleLabel = base?.copyWith(
      fontWeight: FontWeight.w500,
      color: Colors.grey[800],
    );
    final styleValue = base?.copyWith(
      fontWeight: FontWeight.w700,
      color: valueColor ?? Colors.black87,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            alignment: Alignment.centerLeft,
            child: Icon(icon, size: 18, color: valueColor ?? Colors.black87),
          ),
          const SizedBox(width: 2),
          Text('$label: ', style: styleLabel),
          Expanded(
            child: Text(
              value,
              style: styleValue ?? base,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStat extends StatelessWidget {
  const _StatusStat({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$label: $count',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ConnectionStatusBadge extends StatelessWidget {
  const _ConnectionStatusBadge({
    required this.connectionStatus,
    required this.positionsCount,
  });
  final WebSocketStatus connectionStatus;
  final int positionsCount;

  @override
  Widget build(BuildContext context) {
    Color color = Colors.grey;
    var icon = Icons.wifi_off;
    var tooltip = 'Disconnected';
    switch (connectionStatus) {
      case WebSocketStatus.connected:
        color = const Color(0xFFA6CD27); // Green
        icon = Icons.wifi;
        tooltip = 'Connected • $positionsCount positions';
      case WebSocketStatus.connecting:
        color = Colors.orange;
        icon = Icons.wifi_find;
        tooltip = 'Connecting...';
      case WebSocketStatus.retrying:
        color = Colors.orange;
        icon = Icons.wifi_off;
        tooltip = 'Reconnecting...';
      case WebSocketStatus.disconnected:
        color = Colors.grey;
        icon = Icons.wifi_off;
        tooltip = 'Disconnected';
    }

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 4,
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              if (positionsCount > 0 && connectionStatus == WebSocketStatus.connected) ...[
                const SizedBox(width: 4),
                Text(
                  '$positionsCount',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
