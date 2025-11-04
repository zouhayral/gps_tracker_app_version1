import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_permission_service.dart';

/// Provider for checking current location permission status
///
/// Returns the current [LocationPermission] state.
/// This is a [FutureProvider] so it automatically handles loading states.
///
/// Usage:
/// ```dart
/// final permission = ref.watch(geofencePermissionProvider);
/// permission.when(
///   data: (perm) => Text('Permission: $perm'),
///   loading: () => CircularProgressIndicator(),
///   error: (err, stack) => Text('Error: $err'),
/// );
/// ```
final geofencePermissionProvider =
    FutureProvider<LocationPermission>((ref) async {
  final service = ref.read(geofencePermissionServiceProvider);
  return service.checkPermission();
});

/// Provider for checking if background permission is granted
///
/// Returns `true` if LocationPermission.always is granted.
/// Returns `false` for whileInUse, denied, or deniedForever.
///
/// Usage:
/// ```dart
/// final hasBackground = ref.watch(hasBackgroundPermissionProvider);
/// if (hasBackground) {
///   // Show background monitoring UI
/// }
/// ```
final hasBackgroundPermissionProvider = Provider<bool>((ref) {
  final permissionAsync = ref.watch(geofencePermissionProvider);
  
  return permissionAsync.maybeWhen(
    data: (perm) => perm == LocationPermission.always,
    orElse: () => false,
  );
});

/// Provider for checking if any location permission is granted
///
/// Returns `true` if either whileInUse or always permission granted.
/// Useful for determining if basic location access is available.
final hasLocationPermissionProvider = Provider<bool>((ref) {
  final permissionAsync = ref.watch(geofencePermissionProvider);
  
  return permissionAsync.maybeWhen(
    data: (perm) =>
        perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always,
    orElse: () => false,
  );
});

/// Provider for checking if permission is permanently denied
///
/// Returns `true` if LocationPermission.deniedForever.
/// When true, app must direct user to system settings.
final isPermissionPermanentlyDeniedProvider = Provider<bool>((ref) {
  final permissionAsync = ref.watch(geofencePermissionProvider);
  
  return permissionAsync.maybeWhen(
    data: (perm) => perm == LocationPermission.deniedForever,
    orElse: () => false,
  );
});

/// Provider for permission status description
///
/// Returns user-friendly string describing current permission state.
final permissionDescriptionProvider = Provider<String>((ref) {
  final service = ref.read(geofencePermissionServiceProvider);
  final permissionAsync = ref.watch(geofencePermissionProvider);
  
  return permissionAsync.maybeWhen(
    data: service.getPermissionDescription,
    loading: () => 'Checking permission...',
    error: (_, __) => 'Unable to check permission',
    orElse: () => 'Unknown permission status',
  );
});

/// Provider for platform-specific permission guidance
///
/// Returns instructions tailored to Android or iOS.
final permissionGuidanceProvider = Provider<String>((ref) {
  final service = ref.read(geofencePermissionServiceProvider);
  return service.getPermissionGuidance();
});

/// State notifier for managing permission request flow
class PermissionStateNotifier extends StateNotifier<AsyncValue<LocationPermission>> {
  final GeofencePermissionService _service;

  PermissionStateNotifier(this._service)
      : super(const AsyncValue.loading()) {
    // Initial permission check
    _checkPermission();
  }

  /// Check current permission status
  Future<void> _checkPermission() async {
    state = const AsyncValue.loading();
    
    try {
      final perm = await _service.checkPermission();
      state = AsyncValue.data(perm);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Request foreground location permission
  Future<bool> requestForeground() async {
    try {
      final granted = await _service.requestForegroundPermission();
      
      // Refresh permission state
      _checkPermission();
      
      return granted;
    } catch (e) {
      return false;
    }
  }

  /// Request background location permission
  Future<bool> requestBackground() async {
    try {
      final granted = await _service.requestBackgroundPermission();
      
      // Refresh permission state
      _checkPermission();
      
      return granted;
    } catch (e) {
      return false;
    }
  }

  /// Request notification permission (Android 13+)
  Future<bool> requestNotification() async {
    try {
      return await _service.requestNotificationPermission();
    } catch (e) {
      return false;
    }
  }

  /// Open app settings
  Future<bool> openSettings() async {
    final opened = await _service.openAppSettings();
    
    // Wait a bit then refresh permission
    // (in case user changed it in settings)
    if (opened) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _checkPermission();
    }
    
    return opened;
  }

  /// Refresh permission state (call after returning from settings)
  Future<void> refresh() async {
    await _checkPermission();
  }

  /// Get comprehensive permission summary
  Future<Map<String, dynamic>> getSummary() async {
    return _service.getPermissionSummary();
  }
}

/// Provider for permission state notifier
final permissionStateProvider =
    StateNotifierProvider<PermissionStateNotifier, AsyncValue<LocationPermission>>((ref) {
  final service = ref.watch(geofencePermissionServiceProvider);
  return PermissionStateNotifier(service);
});

/// Convenience methods provider for permission operations
final permissionActionsProvider = Provider<PermissionActions>((ref) {
  return PermissionActions(ref);
});

/// Helper class for permission-related actions
class PermissionActions {
  final Ref _ref;

  PermissionActions(this._ref);

  /// Request foreground permission
  Future<bool> requestForeground() async {
    return _ref.read(permissionStateProvider.notifier).requestForeground();
  }

  /// Request background permission
  Future<bool> requestBackground() async {
    return _ref.read(permissionStateProvider.notifier).requestBackground();
  }

  /// Request notification permission
  Future<bool> requestNotification() async {
    return _ref.read(permissionStateProvider.notifier).requestNotification();
  }

  /// Open app settings
  Future<bool> openSettings() async {
    return _ref.read(permissionStateProvider.notifier).openSettings();
  }

  /// Refresh permission state
  Future<void> refresh() async {
    await _ref.read(permissionStateProvider.notifier).refresh();
  }

  /// Get permission summary
  Future<Map<String, dynamic>> getSummary() async {
    return _ref.read(permissionStateProvider.notifier).getSummary();
  }

  /// Check if background permission is granted
  bool get hasBackground => _ref.read(hasBackgroundPermissionProvider);

  /// Check if any location permission is granted
  bool get hasLocation => _ref.read(hasLocationPermissionProvider);

  /// Check if permission is permanently denied
  bool get isPermanentlyDenied => _ref.read(isPermissionPermanentlyDeniedProvider);

  /// Get permission description
  String get description => _ref.read(permissionDescriptionProvider);

  /// Get permission guidance
  String get guidance => _ref.read(permissionGuidanceProvider);
}
