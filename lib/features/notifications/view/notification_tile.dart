import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

    return ListTile(
      onTap: onTap,
      leading: _buildLeadingIcon(context, isUnread),
      title: Row(
        children: [
          Expanded(
            child: Text(
              event.type,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isUnread)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.message != null && event.message!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              event.message!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isUnread
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _formatTimestamp(event.timestamp),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
      trailing: Icon(
        isUnread ? Icons.mark_email_unread : Icons.done,
        color: isUnread ? theme.colorScheme.primary : theme.colorScheme.outline,
        size: 20,
      ),
      tileColor: isUnread
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.1)
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildLeadingIcon(BuildContext context, bool isUnread) {
    final theme = Theme.of(context);
    final iconColor = isUnread
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: event.color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        event.icon,
        color: iconColor,
        size: 24,
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else {
      return DateFormat('MMM d, y • HH:mm').format(timestamp);
    }
  }
}
