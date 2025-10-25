# Geofence Database Setup Guide

**Date**: October 25, 2025  
**Project**: my_app_gps_version2  
**Database**: ObjectBox (primary) + Optional SQLite (for complex spatial queries)

---

## 📊 Current Database Architecture

Your project uses **ObjectBox** as the primary database (see `lib/core/database/objectbox_singleton.dart`). ObjectBox is a high-performance NoSQL database optimized for mobile.

---

## ✅ Approach 1: ObjectBox Integration (RECOMMENDED)

### Step 1: ObjectBox Entities Created

Two new entities have been added:

1. **`GeofenceEntity`** (`lib/core/database/entities/geofence_entity.dart`)
   - Existing entity updated with enhanced documentation
   - Uses WKT format for area (CIRCLE/POLYGON)
   - Stores all custom fields in `attributesJson`

2. **`GeofenceEventEntity`** (`lib/core/database/entities/geofence_event_entity.dart`) ✨ NEW
   - Tracks entry/exit/dwell events
   - Indexed for fast queries by geofence, device, timestamp
   - Includes status tracking and sync management

### Step 2: Run ObjectBox Code Generation

ObjectBox requires code generation to create Box accessors. Run:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This will:
- Generate `objectbox.g.dart` with all entity mappings
- Create database schema migrations automatically
- Add `Box<GeofenceEventEntity>` accessor

### Step 3: Usage in Repository

```dart
import 'package:my_app_gps/core/database/objectbox_singleton.dart';
import 'package:my_app_gps/core/database/entities/geofence_entity.dart';
import 'package:my_app_gps/core/database/entities/geofence_event_entity.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';

class GeofenceRepository {
  Box<GeofenceEntity>? _geofenceBox;
  Box<GeofenceEventEntity>? _eventBox;

  Future<void> init() async {
    final store = await ObjectBoxSingleton.getStore();
    _geofenceBox = store.box<GeofenceEntity>();
    _eventBox = store.box<GeofenceEventEntity>();
  }

  // Create geofence
  Future<void> createGeofence(Geofence geofence) async {
    final entity = geofence.toEntity();
    await _geofenceBox!.putAsync(entity);
  }

  // Get all geofences
  Future<List<Geofence>> getGeofences() async {
    final entities = _geofenceBox!.getAll();
    return entities.map((e) => Geofence.fromEntity(e)).toList();
  }

  // Record geofence event
  Future<void> recordEvent(GeofenceEvent event) async {
    final entity = GeofenceEventEntity.fromDomain(
      eventId: event.id,
      geofenceId: event.geofenceId,
      geofenceName: event.geofenceName,
      deviceId: event.deviceId,
      deviceName: event.deviceName,
      eventType: event.eventType,
      eventTime: event.timestamp,
      latitude: event.latitude,
      longitude: event.longitude,
      dwellDurationMs: event.dwellDurationMs,
      status: event.status,
      syncStatus: event.syncStatus,
    );
    await _eventBox!.putAsync(entity);
  }

  // Query events by geofence
  Stream<List<GeofenceEvent>> watchEventsForGeofence(String geofenceId) {
    final query = _eventBox!
        .query(GeofenceEventEntity_.geofenceId.equals(geofenceId))
        .order(GeofenceEventEntity_.eventTimeMs, flags: Order.descending)
        .build();

    return query.stream().map((entities) =>
        entities.map((e) => GeofenceEvent.fromMap(e.toDomain())).toList());
  }
}
```

### Advantages of ObjectBox

✅ **Automatic migrations** - No SQL scripts needed  
✅ **Fast queries** - Optimized for mobile  
✅ **Type-safe** - Compile-time checking  
✅ **Dart native** - No platform channels  
✅ **Reactive** - Built-in stream support  
✅ **Already integrated** - Matches existing architecture

---

## 🔄 Approach 2: SQLite Co-existence (OPTIONAL)

If you need complex spatial queries or want a separate database for geofences, the SQLite files have been created:

### Files Created

1. **`assets/db/migrations/migration_v5_add_geofences.sql`**
   - Creates `geofences` table
   - Adds indexes for fast queries
   - Includes validation triggers
   - AUTO_UPDATE timestamp trigger

2. **`assets/db/migrations/migration_v5_add_geofence_events.sql`**
   - Creates `geofence_events` table
   - Foreign key to geofences (CASCADE delete)
   - Multiple indexes for common queries
   - Auto-cleanup trigger for old archived events

3. **`lib/core/database/geofence_database.dart`**
   - SQLite database helper
   - Migration runner
   - CRUD helper methods

### Required Dependency

Add to `pubspec.yaml`:

```yaml
dependencies:
  sqflite: ^2.3.0
  path: ^1.8.3
```

### Add Migrations to Assets

Update `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/images/
    - assets/db/migrations/  # Add this line
```

### Usage

```dart
import 'package:my_app_gps/core/database/geofence_database.dart';

// Initialize (creates tables automatically)
final db = await GeofenceDatabase.database;

// Insert geofence
await GeofenceDatabase.insertGeofence(geofence.toMap());

// Query geofences for user
final geofences = await GeofenceDatabase.getGeofences(userId);

// Record event
await GeofenceDatabase.insertEvent(event.toMap());

// Get events for device
final events = await GeofenceDatabase.getEventsForDevice(deviceId);
```

### When to Use SQLite

- ✅ Need complex spatial joins (e.g., "devices in multiple geofences")
- ✅ Want SQL triggers and constraints
- ✅ Prefer JSON field queries (vertices, devices arrays)
- ✅ Need database export/backup (SQLite files are portable)

### When NOT to Use SQLite

- ❌ ObjectBox is sufficient for your use case
- ❌ Don't want to manage two databases
- ❌ Want reactive streams (ObjectBox has better support)

---

## 🎯 Recommended Approach

**Use ObjectBox (Approach 1)** for your project because:

1. Already integrated and working
2. Automatic schema migrations
3. Better performance for mobile
4. Reactive streams match your Riverpod architecture
5. Less complexity (one database system)

---

## 📝 Next Steps (ObjectBox Path)

### 1. Run Code Generation

```bash
cd /path/to/my_app_gps_version2
flutter pub run build_runner build --delete-conflicting-outputs
```

### 2. Verify Generated Files

Check that `lib/objectbox.g.dart` includes:
- `GeofenceEntity_` property accessors
- `GeofenceEventEntity_` property accessors

### 3. Create DAO (Data Access Object)

Create `lib/core/database/dao/geofences_dao.dart`:

```dart
import 'package:objectbox/objectbox.dart';
import 'package:my_app_gps/core/database/entities/geofence_entity.dart';
import 'package:my_app_gps/core/database/entities/geofence_event_entity.dart';
import 'package:my_app_gps/core/database/objectbox_singleton.dart';

class GeofencesDAO {
  Box<GeofenceEntity>? _geofenceBox;
  Box<GeofenceEventEntity>? _eventBox;

  Future<void> init() async {
    final store = await ObjectBoxSingleton.getStore();
    _geofenceBox = store.box<GeofenceEntity>();
    _eventBox = store.box<GeofenceEventEntity>();
  }

  // Geofence methods
  Future<List<GeofenceEntity>> getAllGeofences() async {
    return _geofenceBox!.getAll();
  }

  Future<GeofenceEntity?> getGeofence(int id) async {
    return _geofenceBox!.get(id);
  }

  Future<int> saveGeofence(GeofenceEntity geofence) async {
    return await _geofenceBox!.putAsync(geofence);
  }

  Future<void> deleteGeofence(int id) async {
    await _geofenceBox!.removeAsync(id);
    // Note: Events will need manual cleanup if you want cascade delete
    await deleteEventsForGeofence(id.toString());
  }

  // Event methods
  Future<int> saveEvent(GeofenceEventEntity event) async {
    return await _eventBox!.putAsync(event);
  }

  Future<List<GeofenceEventEntity>> getEventsForGeofence(String geofenceId) async {
    final query = _eventBox!
        .query(GeofenceEventEntity_.geofenceId.equals(geofenceId))
        .order(GeofenceEventEntity_.eventTimeMs, flags: Order.descending)
        .build();
    return query.find();
  }

  Future<void> deleteEventsForGeofence(String geofenceId) async {
    final query = _eventBox!
        .query(GeofenceEventEntity_.geofenceId.equals(geofenceId))
        .build();
    await _eventBox!.removeMany(query.findIds());
  }

  // Stream methods for reactive UI
  Stream<List<GeofenceEntity>> watchGeofences() {
    return _geofenceBox!.query().watch(triggerImmediately: true).map((query) => query.find());
  }

  Stream<List<GeofenceEventEntity>> watchEvents() {
    return _eventBox!
        .query()
        .order(GeofenceEventEntity_.eventTimeMs, flags: Order.descending)
        .watch(triggerImmediately: true)
        .map((query) => query.find());
  }
}
```

### 4. Create Riverpod Provider

Add to `lib/core/providers/database_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/geofences_dao.dart';

final geofencesDAOProvider = Provider<GeofencesDAO>((ref) {
  final dao = GeofencesDAO();
  dao.init();
  return dao;
});
```

### 5. Test the Setup

Create `test/database/geofence_database_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/database/objectbox_singleton.dart';
import 'package:my_app_gps/core/database/entities/geofence_entity.dart';
import 'package:my_app_gps/core/database/entities/geofence_event_entity.dart';

void main() {
  setUp(() async {
    // Reset ObjectBox for each test
    await ObjectBoxSingleton.closeStore();
  });

  test('Can create and retrieve geofence', () async {
    final store = await ObjectBoxSingleton.getStore();
    final box = store.box<GeofenceEntity>();

    final geofence = GeofenceEntity(
      geofenceId: 1,
      name: 'Test Geofence',
      area: 'CIRCLE (33.5731 -7.5898, 500)',
      attributesJson: '{"enabled": true}',
    );

    final id = await box.putAsync(geofence);
    expect(id, greaterThan(0));

    final retrieved = box.get(id);
    expect(retrieved?.name, 'Test Geofence');
  });

  test('Can create and retrieve geofence event', () async {
    final store = await ObjectBoxSingleton.getStore();
    final box = store.box<GeofenceEventEntity>();

    final event = GeofenceEventEntity(
      eventId: 'event_001',
      geofenceId: '1',
      geofenceName: 'Test Geofence',
      deviceId: 'device_001',
      deviceName: 'Test Device',
      eventType: 'enter',
      eventTimeMs: DateTime.now().millisecondsSinceEpoch,
      latitude: 33.5731,
      longitude: -7.5898,
    );

    final id = await box.putAsync(event);
    expect(id, greaterThan(0));

    final retrieved = box.get(id);
    expect(retrieved?.eventType, 'enter');
  });
}
```

---

## 📚 Resources

- **ObjectBox Dart Documentation**: https://docs.objectbox.io/getting-started/dart
- **Your existing DAO example**: `lib/core/database/dao/positions_dao.dart`
- **Geofence Models**: 
  - `lib/data/models/geofence.dart`
  - `lib/data/models/geofence_event.dart`

---

## ✅ Summary

| Aspect | ObjectBox (Recommended) | SQLite (Optional) |
|--------|------------------------|-------------------|
| **Setup Complexity** | Low (already integrated) | Medium (add dependency) |
| **Performance** | Excellent | Good |
| **Migrations** | Automatic | Manual SQL scripts |
| **Type Safety** | Yes | No (dynamic maps) |
| **Reactive Streams** | Built-in | Requires wrapper |
| **Spatial Queries** | Basic | Advanced (with extensions) |
| **Our Recommendation** | ✅ Use this | ⚠️ Only if needed |

**Next Action**: Run `flutter pub run build_runner build` to generate ObjectBox schema! 🚀
