import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_app_gps/core/map/marker_performance_monitor.dart';
import 'package:my_app_gps/core/providers/connectivity_providers.dart';

// ============================================================================
// REBUILD BADGE - Debug overlay for tracking widget rebuilds
// ============================================================================

/// Debug badge that displays rebuild count for a specific widget.
///
/// Useful for identifying unnecessary rebuilds during development.
/// Should only be displayed when MapDebugFlags.showRebuildOverlay is true.
class MapRebuildBadge extends StatefulWidget {
  const MapRebuildBadge({required this.label, super.key});

  final String label;

  @override
  State<MapRebuildBadge> createState() => _MapRebuildBadgeState();
}

class _MapRebuildBadgeState extends State<MapRebuildBadge> {
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

// ============================================================================
// CONNECTIVITY BANNER - WebSocket connection status indicator
// ============================================================================

/// Connectivity banner showing WebSocket reconnection status.
///
/// Displays when the WebSocket connection is lost or reconnecting.
/// Features:
/// - Animated appearance/disappearance
/// - Loading spinner during reconnection
/// - Dismissible with button
/// - Auto-positioning at top of screen
class MapConnectivityBanner extends StatelessWidget {
  const MapConnectivityBanner({
    required this.visible,
    required this.onDismiss,
    this.message = 'Live updates paused • Reconnecting...',
    super.key,
  });

  /// Whether the banner should be visible
  final bool visible;

  /// Callback when user dismisses the banner
  final VoidCallback onDismiss;

  /// Custom message to display (optional)
  final String message;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Dismiss',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// OFFLINE BANNER - Network connectivity status indicator
// ============================================================================

/// Offline/reconnecting banner showing network and connection status.
///
/// Displays different states:
/// - Red: No network connection (offline)
/// - Orange: Unstable connection (reconnecting frequently)
/// - Orange: Reconnecting to server
///
/// Automatically hides when connection is stable and online.
class MapOfflineBanner extends StatelessWidget {
  const MapOfflineBanner({
    required this.networkState,
    required this.connectionStatus,
    super.key,
  });

  final NetworkState networkState;
  final ConnectionStatus connectionStatus;

  @override
  Widget build(BuildContext context) {
    // Determine what to show based on network and connection status
    final isOffline = networkState == NetworkState.offline;
    final isReconnecting = connectionStatus == ConnectionStatus.reconnecting;
    final isUnstable = connectionStatus == ConnectionStatus.unstable;

    // Only show banner if offline, reconnecting, or unstable
    if (!isOffline && !isReconnecting && !isUnstable) {
      return const SizedBox.shrink();
    }

    // Determine banner properties
    Color bgColor;
    IconData icon;
    String message;

    if (isOffline) {
      bgColor = Colors.red.shade700;
      icon = Icons.cloud_off;
      message = 'No network connection - Showing cached data';
    } else if (isUnstable) {
      bgColor = Colors.orange.shade700;
      icon = Icons.warning;
      message = 'Unstable connection - Reconnecting frequently';
    } else {
      // reconnecting
      bgColor = Colors.orange;
      icon = Icons.sync;
      message = 'Reconnecting to server...';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        // External positioning already accounts for the status bar. Disable top padding here
        // to avoid doubling the offset and keep the banner height tight.
        top: false,
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// MARKER PERFORMANCE OVERLAY - Performance monitoring widget
// ============================================================================

/// Marker performance overlay showing cache efficiency and processing time.
///
/// Displays real-time metrics:
/// - Total marker updates
/// - Average processing time (green < 16ms, orange >= 16ms)
/// - Reuse rate percentage (green > 70%, orange <= 70%)
/// - Total markers created vs reused
///
/// Updates every 500ms with current MarkerPerformanceMonitor stats.
class MapMarkerPerformanceOverlay extends StatefulWidget {
  const MapMarkerPerformanceOverlay({super.key});

  @override
  State<MapMarkerPerformanceOverlay> createState() =>
      _MapMarkerPerformanceOverlayState();
}

class _MapMarkerPerformanceOverlayState
    extends State<MapMarkerPerformanceOverlay> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    // Update every 500ms
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = MarkerPerformanceMonitor.instance.getStats();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⚡ Marker Performance',
            style: TextStyle(
              color: Colors.green[300],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          _MapStatRow(
            'Updates',
            stats.totalUpdates.toString(),
            Colors.white70,
          ),
          _MapStatRow(
            'Avg Time',
            '${stats.averageProcessingMs.toStringAsFixed(1)}ms',
            stats.averageProcessingMs < 16
                ? Colors.green[300]!
                : Colors.orange[300]!,
          ),
          _MapStatRow(
            'Reuse',
            '${(stats.averageReuseRate * 100).toStringAsFixed(0)}%',
            stats.averageReuseRate > 0.7
                ? Colors.green[300]!
                : Colors.orange[300]!,
          ),
          _MapStatRow(
            'Created',
            stats.totalCreated.toString(),
            Colors.white70,
          ),
          _MapStatRow(
            'Reused',
            stats.totalReused.toString(),
            Colors.green[300]!,
          ),
        ],
      ),
    );
  }
}

/// Helper widget for displaying key-value stat rows in performance overlay
class _MapStatRow extends StatelessWidget {
  const _MapStatRow(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
