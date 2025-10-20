import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/providers/notification_providers.dart';

/// NotificationBadge displays the unread notification count in the AppBar.
///
/// Features:
/// - Shows badge with unread count
/// - Auto-updates via unreadCountProvider
/// - Hides badge when count is 0
/// - Supports tap callback
class NotificationBadge extends ConsumerWidget {
  const NotificationBadge({
    this.onTap,
    super.key,
  });

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadCountProvider);
    final theme = Theme.of(context);

    return IconButton(
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        label: Text(
          unreadCount > 99 ? '99+' : '$unreadCount',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.error,
        textColor: theme.colorScheme.onError,
        child: Icon(
          unreadCount > 0
              ? Icons.notifications_active
              : Icons.notifications_outlined,
        ),
      ),
      onPressed: onTap,
      tooltip: unreadCount > 0 ? '$unreadCount unread' : 'Notifications',
    );
  }
}
