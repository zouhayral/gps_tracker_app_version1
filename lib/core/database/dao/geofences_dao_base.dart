import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';

/// Abstraction for geofence persistence to enable platform-specific backends.
abstract class GeofencesDaoBase {
  // Geofence operations
  Future<void> upsertGeofence(Geofence geofence);
  Future<void> deleteGeofence(String geofenceId);
  Future<Geofence?> getGeofence(String geofenceId);
  Future<List<Geofence>> getAllGeofences();
  Future<List<Geofence>> getEnabledGeofences();

  // Geofence event operations
  Future<void> insertEvent(GeofenceEvent event);
  Future<List<GeofenceEvent>> getEventsForGeofence(String geofenceId, {int limit = 100});
  Future<List<GeofenceEvent>> getEventsForDevice(String deviceId, {int limit = 100});
  Future<List<GeofenceEvent>> getPendingEvents({int limit = 100});
  Future<void> updateEventStatus(String eventId, String status);
}

// Forward-declared provider (implemented per-platform via conditional import)
late final FutureProvider<GeofencesDaoBase> geofencesDaoProvider;
