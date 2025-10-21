import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';

import 'package:my_app_gps/data/models/event.dart';

/// NotificationTile displays a single event notification.
///
/// Features:
/// - Shows event icon, type, message, and timestamp
/// - Highlights unread events with background color
/// - Displays read/unread indicator
/// - Supports tap callback for marking as read
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    required this.event,
    this.onTap,
    super.key,
  });

  final Event event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !event.isRead;
    final priority = (event.attributes['priority']?.toString() ??
            event.severity?.toLowerCase() ??
            'low')
        .toLowerCase();
    final colors = _paletteForPriority(context, priority);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLeadingIcon(context, isUnread, bg: colors.iconBg, fg: colors.iconFg),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              _titleForEvent(),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          _PriorityBadge(label: priority, color: colors.badgeBg, textColor: colors.badgeFg),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Device name row with device icon and bold name
                      Row(
                        children: [
                          Icon(
                            Icons.devices_other_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurface,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              event.deviceName ?? 'Unknown Device',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if ((event.message ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          (event.message ?? '').trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                Text(
                  _relativeTime(event.timestamp),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeadingIcon(BuildContext context, bool isUnread,
      {required Color bg, required Color fg,}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        event.icon,
        color: fg,
        size: 24,
      ),
    );
  }

  // _formatTimestamp retained in previous design; replaced by _relativeTime

  String _relativeTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes.clamp(0, 59);
      return '$m min';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} h';
    }
    return '${diff.inDays} d';
  }

  String _titleForEvent() {
    // Map known types to user-friendly titles similar to the mock
    final t = event.type.toLowerCase();
    switch (t) {
      case 'deviceoffline':
      case 'device offline':
        return 'device off line';
      case 'geofenceexit':
      case 'geofence exit':
        return 'Geo-fence exit';
      case 'geofenceenter':
        return 'Geo-fence enter';
      case 'ignitionon':
        return 'Ignition on';
      case 'ignitionoff':
        return 'Ignition off';
      default:
        return event.type;
    }
  }

  // Subtitle format replaced by explicit device name row + message text

  _PriorityPalette _paletteForPriority(BuildContext context, String priority) {
    // Colors inspired by the mock: high(red), medium(orange), low(purple)
    switch (priority) {
      case 'high':
        return const _PriorityPalette(
          background: Color(0xFFF1F8E9), // light green background like mock
          border: Color(0xFFE0E6D6),
          iconBg: Color(0xFFFFEBEE),
          iconFg: Color(0xFFD32F2F),
          badgeBg: Color(0xFFE53935),
          badgeFg: Colors.white,
        );
      case 'medium':
        return const _PriorityPalette(
          background: Color(0xFFF1F8E9),
          border: Color(0xFFE0E6D6),
          iconBg: Color(0xFFFFF3E0),
          iconFg: Color(0xFFEF6C00),
          badgeBg: Color(0xFFFF8F00),
          badgeFg: Colors.white,
        );
      default:
        return const _PriorityPalette(
          background: Color(0xFFF1F8E9),
          border: Color(0xFFE0E6D6),
          iconBg: Color(0xFFEDE7F6),
          iconFg: Color(0xFF5E35B1),
          badgeBg: Color(0xFF4E3E67),
          badgeFg: Colors.white,
        );
    }
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.label, required this.color, required this.textColor});
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PriorityPalette {
  const _PriorityPalette({
    required this.background,
    required this.border,
    required this.iconBg,
    required this.iconFg,
    required this.badgeBg,
    required this.badgeFg,
  });
  final Color background;
  final Color border;
  final Color iconBg;
  final Color iconFg;
  final Color badgeBg;
  final Color badgeFg;
}
