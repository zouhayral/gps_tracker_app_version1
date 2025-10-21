import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/features/notifications/view/notification_badge.dart';
import 'package:my_app_gps/features/notifications/view/notification_banner.dart';
import 'package:my_app_gps/features/notifications/view/notification_action_bar.dart';
import 'package:my_app_gps/features/notifications/view/notification_tile.dart';
import 'package:my_app_gps/features/notifications/view/recovered_banner.dart';
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
  // Observe base stream loading state, but never block UI on it
  final baseAsync = ref.watch(notificationsStreamProvider);
  final repo = ref.watch(notificationsRepositoryProvider);
  final events = baseAsync.maybeWhen(
    data: (events) => events,
    orElse: repo.getCurrentEvents,
  );
  final isSearching = baseAsync.isLoading;

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
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // Action bar (Mark all read only)
                const NotificationActionBar(),
                // Non-blocking progress hint (thin bar) while background sync completes
                if (isSearching)
                  const SizedBox(
                    height: 2,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                // Events list
                Expanded(child: _buildEventsList(context, ref, events)),
              ],
            ),
            // Notification banner: also visible on Notifications page
            const Align(
              alignment: Alignment.bottomCenter,
              child: NotificationBanner(),
            ),
            // Recovered events banner: shows count after reconnect backfill
            const Align(
              alignment: Alignment.bottomCenter,
              child: RecoveredEventsBanner(),
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
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final event = events[index];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Dismissible(
              key: ValueKey('event-${event.id}'),
              background: _buildSwipeBackground(context, true),
              secondaryBackground: _buildSwipeBackground(context, false),
              onDismissed: (_) async {
                // Delete the notification locally
                await ref.read(deleteNotificationProvider(event.id).future);
                // Optional: SnackBar undo could be implemented by re-inserting if needed
              },
              child: NotificationTile(
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
                    await Future<void>.delayed(const Duration(milliseconds: 150));
                    _showEventDetails(context, event);
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSwipeBackground(BuildContext context, bool leftToRight) {
    const color = Colors.redAccent;
    final alignment = leftToRight ? Alignment.centerLeft : Alignment.centerRight;
    const icon = Icons.delete_forever_rounded;
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      child: Row(
        mainAxisAlignment:
            leftToRight ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 8),
          const Text(
            'Delete',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
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

  // Removed _buildErrorView: with value provider the UI doesn't
  // block on loading/errors; we always show list/empty state.

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
