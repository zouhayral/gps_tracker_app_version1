import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/features/notifications/view/notification_badge.dart';
import 'package:my_app_gps/features/notifications/view/notification_filter_bar.dart';
import 'package:my_app_gps/features/notifications/view/notification_tile.dart';
import 'package:my_app_gps/features/notifications/view/notification_banner.dart';
import 'package:my_app_gps/providers/notification_providers.dart';

/// NotificationsPage displays a list of notification events with live updates.
///
/// Features:
/// - Real-time event list via notificationsStreamProvider
/// - Unread badge in AppBar via unreadCountProvider
/// - Pull-to-refresh via refreshNotificationsProvider
/// - Mark as read on tap via markEventAsReadProvider
/// - Live toast notifications via NotificationToastListener
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use filtered notifications provider instead of raw stream
    final notificationsAsync = ref.watch(filteredNotificationsProvider);
    final filter = ref.watch(notificationFilterProvider);

    return Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            // Unread count badge
            NotificationBadge(
              onTap: () {
                // Optional: Navigate to unread-only view or mark all as read
              },
            ),
            const SizedBox(width: 8),
            // Clear filters button
            if (filter.isActive)
              IconButton(
                icon: const Icon(Icons.filter_alt_off_outlined),
                iconSize: 24,
                tooltip: 'Clear Filters',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                onPressed: () {
                  // Clear all filters
                  ref.read(notificationFilterProvider.notifier).state =
                      const NotificationFilter();
                  // Refresh the list
                  ref.invalidate(notificationsStreamProvider);
                },
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // Filter bar
                const NotificationFilterBar(),
                // Events list
                Expanded(
                  child: notificationsAsync.when(
                    data: (events) => _buildEventsList(context, ref, events),
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (error, stack) => _buildErrorView(context, ref, error),
                  ),
                ),
              ],
            ),
            // Notification banner: also visible on Notifications page
            const Align(
              alignment: Alignment.bottomCenter,
              child: NotificationBanner(),
            ),
          ],
        ),
      );
    
  }

  Widget _buildEventsList(
    BuildContext context,
    WidgetRef ref,
    List<Event> events,
  ) {
    if (events.isEmpty) {
      return _buildEmptyView(context);
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Trigger refresh from API
        final _ = await ref.refresh(refreshNotificationsProvider.future);
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: events.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final event = events[index];
          return NotificationTile(
            event: event,
            onTap: () async {
              // Mark as read when tapped
              if (!event.isRead) {
                await ref
                    .read(markEventAsReadProvider.notifier)
                    .call(event.id);
              }
              
              // Close any open bottom overlays/toasts before showing details
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
                // If you use overlay support or Flushbar elsewhere, add dismiss hooks here
                await Future<void>.delayed(const Duration(milliseconds: 150));
                _showEventDetails(context, event);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'New events will appear here',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, WidgetRef ref, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load notifications',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              ref.invalidate(notificationsStreamProvider);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final formatter = DateFormat('MMM d, y • HH:mm');
    return formatter.format(timestamp);
  }

  void _showEventDetails(BuildContext context, Event event) {
    // Defensive: ensure any SnackBars are hidden when opening details
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(event.icon, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    event.type,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (event.message != null) ...[
              Text(
                'Message',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                event.message!,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Time',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(event.timestamp),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Device ID: ${event.deviceId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  'Severity: ${event.severity ?? 'N/A'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
