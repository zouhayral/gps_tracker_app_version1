import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Provider for GeofencePermissionService
final geofencePermissionServiceProvider =
    Provider<GeofencePermissionService>((ref) => GeofencePermissionService());

/// Service for managing geofence location permissions across platforms.
///
/// Handles:
/// - Checking current permission state
/// - Requesting foreground (While Using) permissions
/// - Requesting background (Always Allow) permissions
/// - Providing education UX when permissions denied
/// - Graceful fallback to foreground-only monitoring
///
/// Platform Differences:
/// - **Android 10+**: Requires separate background permission request
/// - **Android 13+**: Requires notification permission for foreground service
/// - **iOS**: Single "Always Allow" request; must open Settings manually for upgrade
class GeofencePermissionService {
  final _log = Logger();

  /// Check current location permission status
  ///
  /// Returns:
  /// - `LocationPermission.denied` - Not requested yet
  /// - `LocationPermission.deniedForever` - User permanently denied
  /// - `LocationPermission.whileInUse` - Foreground only
  /// - `LocationPermission.always` - Background access granted
  Future<LocationPermission> checkPermission() async {
    try {
      final perm = await Geolocator.checkPermission();
      _log.i('Current location permission: $perm');
      return perm;
    } catch (e) {
      _log.e('Failed to check permission: $e');
      return LocationPermission.denied;
    }
  }

  /// Request foreground location permission (While Using / When In Use)
  ///
  /// Returns `true` if granted (either whileInUse or always)
  Future<bool> requestForegroundPermission() async {
    try {
      _log.i('Requesting foreground location permission...');
      
      // Check if service is enabled first
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _log.w('Location services are disabled');
        return false;
      }

      final perm = await Geolocator.requestPermission();
      _log.i('Foreground permission result: $perm');
      
      return isGranted(perm);
    } catch (e) {
      _log.e('Failed to request foreground permission: $e');
      return false;
    }
  }

  /// Request background location permission (Always Allow)
  ///
  /// Platform-specific behavior:
  /// - **Android 10+**: Shows system dialog for background access
  /// - **Android 11+**: Shows full-screen settings page
  /// - **iOS**: Cannot upgrade programmatically; returns false if not already granted
  ///
  /// Returns `true` if background access granted
  Future<bool> requestBackgroundPermission() async {
    try {
      _log.i('Requesting background location permission...');

      // First ensure foreground is granted
      final currentPerm = await checkPermission();
      if (!isGranted(currentPerm)) {
        _log.w('Foreground permission not granted, requesting first...');
        final foregroundGranted = await requestForegroundPermission();
        if (!foregroundGranted) {
          _log.e('Cannot request background without foreground permission');
          return false;
        }
      }

      // Platform-specific background request
      if (Platform.isAndroid) {
        return await _requestAndroidBackgroundPermission();
      } else if (Platform.isIOS) {
        return await _requestIOSBackgroundPermission();
      }

      _log.w('Unsupported platform for background permission');
      return false;
    } catch (e) {
      _log.e('Failed to request background permission: $e');
      return false;
    }
  }

  /// Android-specific background permission request
  Future<bool> _requestAndroidBackgroundPermission() async {
    try {
      // Check Android version
      if (Platform.isAndroid) {
        // Android 10+ (API 29+) requires separate background permission
        final backgroundStatus = await ph.Permission.locationAlways.status;
        _log.i('Current Android background status: $backgroundStatus');

        if (backgroundStatus.isGranted) {
          _log.i('Background permission already granted');
          return true;
        }

        // Request background permission
        final result = await ph.Permission.locationAlways.request();
        _log.i('Background permission request result: $result');

        if (result.isGranted) {
          _log.i('✅ Background permission granted');
          return true;
        } else if (result.isPermanentlyDenied) {
          _log.w('⛔ Background permission permanently denied');
          return false;
        } else {
          _log.w('❌ Background permission denied');
          return false;
        }
      }
      return false;
    } catch (e) {
      _log.e('Android background permission error: $e');
      return false;
    }
  }

  /// iOS-specific background permission request
  Future<bool> _requestIOSBackgroundPermission() async {
    try {
      // iOS requires "Always Allow" selection in system dialog
      // Cannot be upgraded programmatically after initial denial
      final perm = await Geolocator.requestPermission();
      
      if (perm == LocationPermission.always) {
        _log.i('✅ iOS always permission granted');
        return true;
      } else if (perm == LocationPermission.whileInUse) {
        _log.w('⚠️ iOS only granted "While Using" - user must upgrade in Settings');
        return false;
      } else {
        _log.w('❌ iOS permission denied: $perm');
        return false;
      }
    } catch (e) {
      _log.e('iOS background permission error: $e');
      return false;
    }
  }

  /// Check if notification permission is granted (Android 13+ requirement)
  ///
  /// Android 13+ requires notification permission for foreground services
  Future<bool> checkNotificationPermission() async {
    if (!Platform.isAndroid) return true; // iOS handles separately

    try {
      final status = await ph.Permission.notification.status;
      _log.i('Notification permission status: $status');
      return status.isGranted;
    } catch (e) {
      _log.e('Failed to check notification permission: $e');
      return false;
    }
  }

  /// Request notification permission (Android 13+)
  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;

    try {
      _log.i('Requesting notification permission...');
      final status = await ph.Permission.notification.request();
      _log.i('Notification permission result: $status');
      return status.isGranted;
    } catch (e) {
      _log.e('Failed to request notification permission: $e');
      return false;
    }
  }

  /// Open app settings page
  ///
  /// Use when user needs to manually enable permissions
  Future<bool> openAppSettings() async {
    try {
      _log.i('Opening app settings...');
      return await ph.openAppSettings();
    } catch (e) {
      _log.e('Failed to open app settings: $e');
      return false;
    }
  }

  /// Check if permission is granted (either whileInUse or always)
  bool isGranted(LocationPermission perm) =>
      perm == LocationPermission.whileInUse || 
      perm == LocationPermission.always;

  /// Check if background permission is granted
  bool hasBackground(LocationPermission perm) =>
      perm == LocationPermission.always;

  /// Check if permission is permanently denied
  bool isPermanentlyDenied(LocationPermission perm) =>
      perm == LocationPermission.deniedForever;

  /// Get user-friendly permission status description
  String getPermissionDescription(LocationPermission perm) {
    switch (perm) {
      case LocationPermission.denied:
        return 'Location permission not granted';
      case LocationPermission.deniedForever:
        return 'Location permission permanently denied';
      case LocationPermission.whileInUse:
        return 'Foreground location access (While Using)';
      case LocationPermission.always:
        return 'Background location access (Always Allow)';
      case LocationPermission.unableToDetermine:
        return 'Unable to determine permission status';
    }
  }

  /// Get platform-specific permission guidance
  String getPermissionGuidance() {
    if (Platform.isAndroid) {
      return 'On Android 10+, you need to grant "Allow all the time" '
          'permission for background geofence monitoring.';
    } else if (Platform.isIOS) {
      return 'On iOS, select "Always Allow" when prompted for location access. '
          'You can change this in Settings > Privacy > Location Services.';
    }
    return 'Location permission required for geofence monitoring.';
  }

  /// Comprehensive permission check with all required permissions
  ///
  /// Returns map with permission states:
  /// - `location`: LocationPermission status
  /// - `background`: bool (has background access)
  /// - `notification`: bool (has notification permission, Android 13+ only)
  /// - `ready`: bool (all required permissions granted)
  Future<Map<String, dynamic>> getPermissionSummary() async {
    final locationPerm = await checkPermission();
    final hasNotification = await checkNotificationPermission();

    final summary = {
      'location': locationPerm,
      'background': hasBackground(locationPerm),
      'notification': hasNotification,
      'foreground': isGranted(locationPerm),
      'ready': hasBackground(locationPerm) && hasNotification,
      'description': getPermissionDescription(locationPerm),
      'guidance': getPermissionGuidance(),
    };

    _log.i('Permission summary: $summary');
    return summary;
  }
}
