# Notification System Implementation Guide

**Quick Reference for Adding Notifications Feature**

---

## File Creation Checklist

### 1. Domain Model ✅
**File:** `lib/data/models/event.dart`

```dart
class Event {
  final String id;
  final int deviceId;
  final String type;  // 'deviceOnline', 'deviceOffline', 'alarm', 'geofenceEnter', etc.
  final DateTime timestamp;
  final String? message;
  final String? severity;  // 'info', 'warning', 'critical'
  final int? positionId;
  final int? geofenceId;
  final Map<String, dynamic> attributes;
  final bool isRead;

  Event({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.timestamp,
    this.message,
    this.severity,
    this.positionId,
    this.geofenceId,
    this.attributes = const {},
    this.isRead = false,
  });

  factory Event.fromJson(Map<String, dynamic> json) { /* ... */ }
  Map<String, dynamic> toJson() { /* ... */ }
  
  // Convert to/from ObjectBox entity
  EventEntity toEntity() { /* ... */ }
  factory Event.fromEntity(EventEntity entity) { /* ... */ }
  
  // UI helpers
  IconData get icon { /* ... */ }
  Color get color { /* ... */ }
  String get formattedMessage { /* ... */ }
}
```

---

### 2. Service Layer ✅
**File:** `lib/services/event_service.dart`

```dart
class EventService {
  EventService({required this.dio});
  final Dio dio;

  // Fetch events from Traccar API
  Future<List<Event>> fetchEvents({
    int? deviceId,
    DateTime? from,
    DateTime? to,
    String? type,
  }) async {
    final queryParams = <String, dynamic>{};
    if (deviceId != null) queryParams['deviceId'] = deviceId;
    if (from != null) queryParams['from'] = from.toUtc().toIso8601String();
    if (to != null) queryParams['to'] = to.toUtc().toIso8601String();
    if (type != null) queryParams['type'] = type;

    final response = await dio.get('/api/events', queryParameters: queryParams);
    final List data = response.data as List;
    return data.map((json) => Event.fromJson(json)).toList();
  }

  // Mark event as read (custom endpoint or local-only flag)
  Future<void> markAsRead(String eventId) async {
    // Implementation depends on backend support
  }
}

// Riverpod provider
final eventServiceProvider = Provider<EventService>((ref) {
  final dio = ref.watch(dioProvider);
  return EventService(dio: dio);
});
```

---

### 3. Repository ✅
**File:** `lib/features/notifications/data/notifications_repository.dart`

```dart
class NotificationsRepository {
  NotificationsRepository({
    required this.eventService,
    required this.eventsDao,
    required Ref ref,
  }) {
    // Listen to WebSocket for live events
    ref.listen(customerWebSocketProvider, (previous, next) {
      next.whenData((message) {
        if (message is CustomerEventsMessage) {
          _processLiveEvents(message.events);
        }
      });
    });
  }

  final EventService eventService;
  final EventsDao eventsDao;
  final _controller = StreamController<List<Event>>.broadcast();

  Stream<List<Event>> get stream => _controller.stream;

  Future<void> _processLiveEvents(dynamic eventsData) async {
    final List events = eventsData is List ? eventsData : [eventsData];
    for (final eventJson in events) {
      final event = Event.fromJson(eventJson);
      await eventsDao.insert(event.toEntity());
    }
    await refreshFromDatabase();
  }

  Future<void> refreshFromDatabase({
    int? deviceId,
    String? type,
    int limit = 50,
  }) async {
    final entities = await eventsDao.getRecent(
      deviceId: deviceId,
      type: type,
      limit: limit,
    );
    final events = entities.map(Event.fromEntity).toList();
    _controller.add(events);
  }

  Future<void> syncFromApi({
    DateTime? from,
    DateTime? to,
  }) async {
    final events = await eventService.fetchEvents(from: from, to: to);
    for (final event in events) {
      await eventsDao.upsert(event.toEntity());
    }
    await refreshFromDatabase();
  }

  void dispose() {
    _controller.close();
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  final repo = NotificationsRepository(
    eventService: ref.watch(eventServiceProvider),
    eventsDao: ref.watch(eventsDaoProvider),
    ref: ref,
  );
  ref.onDispose(repo.dispose);
  return repo;
});
```

---

### 4. Providers ✅
**File:** `lib/features/notifications/providers/notifications_provider.dart`

```dart
// Real-time stream of notifications
final notificationsStreamProvider = StreamProvider.autoDispose<List<Event>>((ref) {
  final repo = ref.watch(notificationsRepositoryProvider);
  
  // Initial load from database
  repo.refreshFromDatabase();
  
  return repo.stream;
});

// Filtered notifications
final filteredNotificationsProvider = Provider.autoDispose.family<List<Event>, NotificationFilter>(
  (ref, filter) {
    final events = ref.watch(notificationsStreamProvider).valueOrNull ?? [];
    return events.where((event) {
      if (filter.deviceId != null && event.deviceId != filter.deviceId) return false;
      if (filter.type != null && event.type != filter.type) return false;
      if (filter.onlyUnread && event.isRead) return false;
      return true;
    }).toList();
  },
);

// Unread count (for badge)
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final events = ref.watch(notificationsStreamProvider).valueOrNull ?? [];
  return events.where((e) => !e.isRead).length;
});

// Live event toast (single event stream)
final liveNotificationEventProvider = StreamProvider.autoDispose<Event>((ref) async* {
  await for (final message in ref.watch(customerWebSocketProvider.stream)) {
    if (message is CustomerEventsMessage) {
      final List events = message.events is List ? message.events : [message.events];
      for (final eventJson in events) {
        yield Event.fromJson(eventJson);
      }
    }
  }
});
```

**File:** `lib/features/notifications/providers/notification_filter.dart`

```dart
class NotificationFilter {
  final int? deviceId;
  final String? type;
  final bool onlyUnread;

  const NotificationFilter({
    this.deviceId,
    this.type,
    this.onlyUnread = false,
  });
}

final notificationFilterProvider = StateProvider.autoDispose<NotificationFilter>(
  (ref) => const NotificationFilter(),
);
```

---

### 5. State Management ✅
**File:** `lib/features/notifications/controller/notifications_state.dart`

```dart
class NotificationsState {
  final List<Event> events;
  final bool isLoading;
  final String? error;
  final bool hasMore;

  const NotificationsState({
    this.events = const [],
    this.isLoading = false,
    this.error,
    this.hasMore = true,
  });

  NotificationsState copyWith({
    List<Event>? events,
    bool? isLoading,
    String? error,
    bool? hasMore,
  }) {
    return NotificationsState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}
```

**File:** `lib/features/notifications/controller/notifications_notifier.dart`

```dart
class NotificationsNotifier extends StateNotifier<NotificationsState> {
  NotificationsNotifier(this.ref) : super(const NotificationsState()) {
    _init();
  }

  final Ref ref;

  void _init() {
    // Listen to stream and update state
    ref.listen(notificationsStreamProvider, (previous, next) {
      next.when(
        data: (events) => state = state.copyWith(events: events, isLoading: false),
        loading: () => state = state.copyWith(isLoading: true),
        error: (err, stack) => state = state.copyWith(error: err.toString(), isLoading: false),
      );
    });
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final repo = ref.read(notificationsRepositoryProvider);
    await repo.syncFromApi();
  }

  Future<void> markAsRead(String eventId) async {
    final service = ref.read(eventServiceProvider);
    await service.markAsRead(eventId);
    // Update local state
    final updatedEvents = state.events.map((e) {
      if (e.id == eventId) return e.copyWith(isRead: true);
      return e;
    }).toList();
    state = state.copyWith(events: updatedEvents);
  }

  void filterByDevice(int? deviceId) {
    ref.read(notificationFilterProvider.notifier).state = 
      ref.read(notificationFilterProvider).copyWith(deviceId: deviceId);
  }
}

final notificationsNotifierProvider = StateNotifierProvider.autoDispose<NotificationsNotifier, NotificationsState>(
  (ref) => NotificationsNotifier(ref),
);
```

---

### 6. UI Components ✅

**File:** `lib/features/notifications/view/notifications_page.dart`

```dart
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(notificationFilterProvider);
    final eventsAsync = ref.watch(filteredNotificationsProvider(filter));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterSheet(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(notificationsNotifierProvider.notifier).refresh(),
          ),
        ],
      ),
      body: eventsAsync.when(
        data: (events) => events.isEmpty
            ? const Center(child: Text('No notifications'))
            : ListView.builder(
                itemCount: events.length,
                itemBuilder: (context, index) {
                  return NotificationCard(event: events[index]);
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => NotificationFilterSheet(),
    );
  }
}
```

**File:** `lib/features/notifications/view/notification_card.dart`

```dart
class NotificationCard extends ConsumerWidget {
  const NotificationCard({required this.event, super.key});
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(event.icon, color: event.color),
        title: Text(event.type),
        subtitle: Text(event.formattedMessage),
        trailing: Text(_formatTimestamp(event.timestamp)),
        onTap: () {
          ref.read(notificationsNotifierProvider.notifier).markAsRead(event.id);
          // Navigate to device on map
          context.go('/map?deviceId=${event.deviceId}');
        },
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
```

**File:** `lib/features/notifications/view/notification_toast.dart`

```dart
class NotificationToastListener extends ConsumerWidget {
  const NotificationToastListener({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(liveNotificationEventProvider, (previous, next) {
      next.whenData((event) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(event.icon, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(event.type, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(event.formattedMessage),
                    ],
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            backgroundColor: event.color,
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () => context.go('/notifications'),
            ),
          ),
        );
      });
    });

    return child;
  }
}
```

---

## Integration Steps

### Step 1: Update App Router
**File:** `lib/app/app_router.dart`

```dart
GoRoute(
  path: '/notifications',
  builder: (context, state) => const NotificationsPage(),
),
```

### Step 2: Add Navigation Button
**In Dashboard or AppBar:**

```dart
IconButton(
  icon: Badge(
    label: Text('${ref.watch(unreadNotificationCountProvider)}'),
    isLabelVisible: ref.watch(unreadNotificationCountProvider) > 0,
    child: const Icon(Icons.notifications),
  ),
  onPressed: () => context.go('/notifications'),
)
```

### Step 3: Wrap App with Toast Listener
**File:** `lib/app/app_root.dart`

```dart
@override
Widget build(BuildContext context) {
  final router = ref.watch(goRouterProvider);
  return NotificationToastListener(  // Add this wrapper
    child: MaterialApp.router(
      title: 'GPS Tracker',
      routerConfig: router,
    ),
  );
}
```

---

## Testing Checklist

- [ ] WebSocket connection sends `CustomerEventsMessage`
- [ ] Events are inserted into ObjectBox via `EventsDao`
- [ ] `notificationsStreamProvider` emits updated list
- [ ] UI rebuilds automatically when new event arrives
- [ ] Toast notification appears for live events
- [ ] Tapping notification navigates to device on map
- [ ] Filter sheet works (by device, type, unread)
- [ ] Unread badge count updates
- [ ] Pull-to-refresh syncs from API

---

## WebSocket Event Format

**Traccar sends:**
```json
{
  "type": "events",
  "events": [
    {
      "id": "12345",
      "deviceId": 1,
      "type": "deviceOnline",
      "serverTime": "2025-10-20T10:30:00.000Z",
      "positionId": 67890,
      "attributes": {}
    }
  ]
}
```

**Your code receives:**
```dart
CustomerEventsMessage(events: [
  {
    "id": "12345",
    "deviceId": 1,
    "type": "deviceOnline",
    // ...
  }
])
```

---

## Event Types Reference

| Type | Icon | Color | Description |
|------|------|-------|-------------|
| `deviceOnline` | `Icons.check_circle` | Green | Device connected |
| `deviceOffline` | `Icons.offline_bolt` | Red | Device disconnected |
| `alarm` | `Icons.warning` | Orange | Generic alarm |
| `geofenceEnter` | `Icons.location_on` | Blue | Entered geofence |
| `geofenceExit` | `Icons.location_off` | Purple | Exited geofence |
| `ignitionOn` | `Icons.power` | Green | Ignition turned on |
| `ignitionOff` | `Icons.power_off` | Grey | Ignition turned off |
| `sos` | `Icons.emergency` | Red | Emergency button |

---

## Common Pitfalls

1. **Forgetting to dispose streams:** Always use `ref.onDispose()` in repositories
2. **Not handling empty events:** Check `events is List` before iterating
3. **Missing ObjectBox indexing:** Ensure `@Index()` on frequently queried fields
4. **WebSocket disconnects:** Test offline/online transitions
5. **Memory leaks:** Use `autoDispose` on all providers that depend on streams

---

## Performance Tips

- Use `StreamProvider.autoDispose` to clean up when page is not visible
- Limit `ListView` items with pagination (e.g., 50 per page)
- Debounce filter changes to avoid excessive database queries
- Cache event icons and colors in Event model
- Use `const` constructors for widgets

---

**End of Guide**
