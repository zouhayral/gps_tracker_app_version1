import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/services/customer/customer_websocket.dart';

/// NotificationToastListener listens for new WebSocket events and shows toasts.
///
/// Features:
/// - Listens to customerWebSocketProvider for new events
/// - Shows SnackBar when new event arrives
/// - Includes event type and message
/// - Auto-dismisses after 4 seconds
class NotificationToastListener extends ConsumerStatefulWidget {
  const NotificationToastListener({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  ConsumerState<NotificationToastListener> createState() =>
      _NotificationToastListenerState();
}

class _NotificationToastListenerState
    extends ConsumerState<NotificationToastListener> {
  void _handleNewEvents(dynamic eventsData) {
    if (!mounted) return;

    // Parse the first event to show in toast
    String? eventType;
    String? eventMessage;

    try {
      if (eventsData is List && eventsData.isNotEmpty) {
        final firstEvent = eventsData.first;
        if (firstEvent is Map<String, dynamic>) {
          eventType = firstEvent['type'] as String?;
          eventMessage = firstEvent['message'] as String?;
        }
      } else if (eventsData is Map<String, dynamic>) {
        eventType = eventsData['type'] as String?;
        eventMessage = eventsData['message'] as String?;
      }

      if (eventType != null) {
        _showToast(eventType, eventMessage);
      }
    } catch (e) {
      // Silently fail - don't disrupt user experience
      debugPrint('[NotificationToast] Failed to parse event: $e');
    }
  }

  void _showToast(String eventType, String? message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.notification_important,
              color: theme.colorScheme.onPrimaryContainer,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    eventType,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  if (message != null && message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onPrimaryContainer
                            .withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        backgroundColor: theme.colorScheme.primaryContainer,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View',
          textColor: theme.colorScheme.primary,
          onPressed: () {
            // Navigate to notifications page
            // (handled by parent navigation)
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to WebSocket messages for new events
    ref.listen<AsyncValue<CustomerWebSocketMessage>>(
      customerWebSocketProvider,
      (previous, next) {
        next.whenData((message) {
          if (message is CustomerEventsMessage) {
            _handleNewEvents(message.events);
          }
        });
      },
    );

    return widget.child;
  }
}
