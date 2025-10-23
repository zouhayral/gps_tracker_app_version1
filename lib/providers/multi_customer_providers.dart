/// Multi-Customer Providers
///
/// This file exports all Riverpod providers needed for multi-customer support.
/// Import this file to access all customer-related functionality.
///
/// Architecture flow:
/// - CustomerCredentials (StateProvider)
/// - CustomerSession (FutureProvider)
/// - CustomerWebSocket (StreamProvider)
/// - CustomerDevicePositions (StreamProvider)
/// - CustomerManager (Provider)
///
/// When credentials change → entire cascade rebuilds automatically
library;

// Additional providers for trips and notifications
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/services/customer/customer_service.dart';

export 'package:my_app_gps/features/auth/controller/auth_notifier.dart';
export 'package:my_app_gps/features/auth/controller/auth_state.dart';
// Core providers
export 'package:my_app_gps/services/auth_service.dart';
// Customer service (existing implementation)
export 'package:my_app_gps/services/customer/customer_service.dart';

/// Trips Provider
///
/// Fetches trips for a specific device using the current customer session.
/// Automatically rebuilds when customer logs in/out.
///
/// Usage:
/// ```dart
/// final tripsAsync = ref.watch(tripsProvider((deviceId: 123, from: date1, to: date2)));
/// ```
final tripsProvider = FutureProvider.autoDispose.family<
    List<Map<String, dynamic>>, ({int deviceId, DateTime from, DateTime to})>(
  (ref, params) async {
    // Wait for customer to be logged in
    final session = await ref.watch(customerSessionProvider.future);

    if (!session.isAuthenticated || session.sessionId == null) {
      return [];
    }

    try {
      // Use the session's HTTP client to make the request
      final fromStr = params.from.toUtc().toIso8601String();
      final toStr = params.to.toUtc().toIso8601String();

      // Note: Implement this method in your AuthService or use direct HTTP call
      // For now, return empty list as placeholder
      if (kDebugMode) {
        print(
            '[TripsProvider] Fetching trips for device ${params.deviceId} from $fromStr to $toStr',);
      }

      // TODO(app-team): Implement actual API call
      // final response = await http.get('/api/reports/trips?deviceId=${params.deviceId}&from=$fromStr&to=$toStr');
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('[TripsProvider] Error fetching trips: $e');
      }
      rethrow;
    }
  },
);

/// All Trips Provider (for all devices)
///
/// Fetches trips for all customer devices.
/// Useful for showing a complete trip history.
final allTripsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({DateTime from, DateTime to})>(
  (ref, params) async {
    final session = await ref.watch(customerSessionProvider.future);

    if (!session.isAuthenticated || session.sessionId == null) {
      return [];
    }

    try {
      // Get all device IDs from customer positions
      final deviceIds = ref.read(customerDeviceIdsProvider);

      if (deviceIds.isEmpty) {
        return [];
      }

      if (kDebugMode) {
        print(
            '[AllTripsProvider] Fetching trips for ${deviceIds.length} devices',);
      }

      // TODO(app-team): Implement actual API call
      // final response = await http.get('/api/reports/trips?deviceId=$deviceIdsParam&from=$fromStr&to=$toStr');
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('[AllTripsProvider] Error fetching trips: $e');
      }
      rethrow;
    }
  },
);

/// Notifications Provider
///
/// Fetches notifications from Traccar API using current customer session.
/// Automatically rebuilds when customer logs in/out.
///
/// Also listens to live notification events from WebSocket.
final notificationsProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  final session = await ref.watch(customerSessionProvider.future);

  if (!session.isAuthenticated || session.sessionId == null) {
    yield [];
    return;
  }

  final controller = StreamController<List<Map<String, dynamic>>>();

  // Fetch initial notifications from API (placeholder)
  try {
    if (kDebugMode) {
      print('[NotificationsProvider] Fetching notifications');
    }

    // TODO(app-team): Implement actual API call
    // final response = await http.get('/api/notifications');
    controller.add([]);
  } catch (e) {
    if (kDebugMode) {
      print('[NotificationsProvider] Error fetching notifications: $e');
    }
    controller.add([]);
  }

  // Listen to live WebSocket events
  final subscription = ref.listen<AsyncValue<CustomerWebSocketMessage>>(
    customerWebSocketProvider,
    (previous, next) {
      next.whenData((message) {
        if (message is CustomerEventsMessage) {
          // Add new events to notifications list
          final events = message.events as List<dynamic>? ?? [];
          if (events.isNotEmpty && controller.hasListener) {
            // Stream the events (they come as a list)
            for (final event in events) {
              if (event is Map<String, dynamic>) {
                controller.add([event]);
              }
            }
          }
        }
      });
    },
  );

  // Cleanup
  ref.onDispose(() {
    subscription.close();
    controller.close();
  });

  yield* controller.stream;
});

/// Live Notification Events Provider
///
/// Streams only live notification events from WebSocket.
/// Does NOT include historical notifications from API.
///
/// Usage:
/// ```dart
/// ref.listen(liveNotificationEventsProvider, (previous, next) {
///   next.whenData((event) {
///     // Show notification toast
///     ScaffoldMessenger.of(context).showSnackBar(...);
///   });
/// });
/// ```
final liveNotificationEventsProvider =
    StreamProvider.autoDispose<Map<String, dynamic>>((ref) async* {
  final session = await ref.watch(customerSessionProvider.future);

  if (!session.isAuthenticated) {
    return;
  }

  final controller = StreamController<Map<String, dynamic>>();

  // Listen to WebSocket events
  final subscription = ref.listen<AsyncValue<CustomerWebSocketMessage>>(
    customerWebSocketProvider,
    (previous, next) {
      next.whenData((message) {
        if (message is CustomerEventsMessage) {
          // Events come as a list from Traccar
          final events = message.events as List<dynamic>? ?? [];
          for (final event in events) {
            if (event is Map<String, dynamic>) {
              controller.add(event);
            }
          }
        }
      });
    },
  );

  ref.onDispose(() {
    subscription.close();
    controller.close();
  });

  yield* controller.stream;
});

/// Current User Provider
///
/// Provides the current logged-in customer's user data.
/// Returns null if not logged in.
final currentCustomerProvider =
    Provider.autoDispose<Map<String, dynamic>?>((ref) {
  final session = ref.watch(customerSessionProvider).value;
  return session?.userData;
});

/// Is Customer Logged In Provider
///
/// Simple boolean check for authentication status.
final isCustomerLoggedInProvider = Provider.autoDispose<bool>((ref) {
  final session = ref.watch(customerSessionProvider).value;
  return session?.isAuthenticated ?? false;
});
