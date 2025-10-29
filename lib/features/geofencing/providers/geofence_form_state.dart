import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/features/geofencing/ui/geofence_form_page.dart';

/// Form state for geofence creation/editing
class GeofenceFormState {
  final GeofenceType type;
  final LatLng? circleCenter;
  final double circleRadius;
  final List<LatLng> polygonVertices;
  final bool onEnter;
  final bool onExit;
  final bool enableDwell;
  final double dwellMinutes;
  final Set<String> selectedDevices;
  final bool allDevices;
  final String notificationType;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final String priority;
  final bool isLoading;
  final bool isSaving;

  const GeofenceFormState({
    this.type = GeofenceType.circle,
    this.circleCenter,
    this.circleRadius = 100,
    this.polygonVertices = const [],
    this.onEnter = true,
    this.onExit = true,
    this.enableDwell = false,
    this.dwellMinutes = 5,
    this.selectedDevices = const {},
    this.allDevices = false,
    this.notificationType = 'local',
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.priority = 'default',
    this.isLoading = false,
    this.isSaving = false,
  });

  GeofenceFormState copyWith({
    GeofenceType? type,
    LatLng? circleCenter,
    double? circleRadius,
    List<LatLng>? polygonVertices,
    bool? onEnter,
    bool? onExit,
    bool? enableDwell,
    double? dwellMinutes,
    Set<String>? selectedDevices,
    bool? allDevices,
    String? notificationType,
    bool? soundEnabled,
    bool? vibrationEnabled,
    String? priority,
    bool? isLoading,
    bool? isSaving,
  }) {
    return GeofenceFormState(
      type: type ?? this.type,
      circleCenter: circleCenter ?? this.circleCenter,
      circleRadius: circleRadius ?? this.circleRadius,
      polygonVertices: polygonVertices ?? this.polygonVertices,
      onEnter: onEnter ?? this.onEnter,
      onExit: onExit ?? this.onExit,
      enableDwell: enableDwell ?? this.enableDwell,
      dwellMinutes: dwellMinutes ?? this.dwellMinutes,
      selectedDevices: selectedDevices ?? this.selectedDevices,
      allDevices: allDevices ?? this.allDevices,
      notificationType: notificationType ?? this.notificationType,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      priority: priority ?? this.priority,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

/// Notifier for managing geofence form state
class GeofenceFormNotifier extends StateNotifier<GeofenceFormState> {
  GeofenceFormNotifier() : super(const GeofenceFormState());

  void setType(GeofenceType type) {
    state = state.copyWith(type: type);
  }

  void setCircleCenter(LatLng center) {
    state = state.copyWith(circleCenter: center);
  }

  void setCircleRadius(double radius) {
    state = state.copyWith(circleRadius: radius);
  }

  void setPolygonVertices(List<LatLng> vertices) {
    state = state.copyWith(polygonVertices: vertices);
  }

  void setOnEnter(bool value) {
    state = state.copyWith(onEnter: value);
  }

  void setOnExit(bool value) {
    state = state.copyWith(onExit: value);
  }

  void setEnableDwell(bool value) {
    state = state.copyWith(enableDwell: value);
  }

  void setDwellMinutes(double minutes) {
    state = state.copyWith(dwellMinutes: minutes);
  }

  void toggleDevice(String deviceId) {
    final devices = Set<String>.from(state.selectedDevices);
    if (devices.contains(deviceId)) {
      devices.remove(deviceId);
    } else {
      devices.add(deviceId);
    }
    state = state.copyWith(selectedDevices: devices);
  }

  void setAllDevices(bool value) {
    state = state.copyWith(
      allDevices: value,
      selectedDevices: value ? {} : state.selectedDevices,
    );
  }

  void setNotificationType(String type) {
    state = state.copyWith(notificationType: type);
  }

  void setSoundEnabled(bool value) {
    state = state.copyWith(soundEnabled: value);
  }

  void setVibrationEnabled(bool value) {
    state = state.copyWith(vibrationEnabled: value);
  }

  void setPriority(String priority) {
    state = state.copyWith(priority: priority);
  }

  void setLoading(bool value) {
    state = state.copyWith(isLoading: value);
  }

  void setSaving(bool value) {
    state = state.copyWith(isSaving: value);
  }

  void loadFromGeofence(Geofence geofence) {
    state = GeofenceFormState(
      type: geofence.type == 'circle'
          ? GeofenceType.circle
          : GeofenceType.polygon,
      circleCenter: geofence.type == 'circle'
          ? LatLng(geofence.centerLat!, geofence.centerLng!)
          : null,
      circleRadius: geofence.radius ?? 100.0,
      polygonVertices: geofence.vertices ?? [],
      onEnter: geofence.onEnter,
      onExit: geofence.onExit,
      enableDwell: geofence.dwellMs != null && geofence.dwellMs! > 0,
      dwellMinutes:
          geofence.dwellMs != null ? geofence.dwellMs! / 60000.0 : 5.0,
      selectedDevices: geofence.monitoredDevices.toSet(),
      allDevices: geofence.monitoredDevices.isEmpty,
      notificationType: geofence.notificationType,
    );
  }

  void reset() {
    state = const GeofenceFormState();
  }
}

/// Provider for geofence form state
final geofenceFormProvider =
    StateNotifierProvider.autoDispose<GeofenceFormNotifier, GeofenceFormState>(
  (ref) => GeofenceFormNotifier(),
);
