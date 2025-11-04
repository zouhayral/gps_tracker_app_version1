import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/core/performance/icon_precache_service.dart';
import 'package:my_app_gps/data/models/event.dart';
// Debug HUD disabled globally; overlay imports removed
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_position_feeder.dart';
import 'package:my_app_gps/features/geofencing/diagnostics/geofence_health_overlay.dart';
import 'package:my_app_gps/features/localization/locale_provider.dart';
import 'package:my_app_gps/features/map/view/marker_assets.dart';

import 'package:my_app_gps/l10n/app_localizations.dart';
import 'package:my_app_gps/providers/notification_providers.dart';
import 'package:my_app_gps/repositories/trip_repository.dart';
import 'package:my_app_gps/services/notification_service.dart';
import 'package:my_app_gps/theme/app_theme.dart';

// Debug toggle for Geofence Health overlay
const bool _showGeofenceOverlay = true;

/// Lifecycle observer to automatically clean up expired trip cache
/// when the app goes to background or becomes inactive
class _TripRepositoryLifecycleObserver with WidgetsBindingObserver {
  final TripRepository tripRepository;

  _TripRepositoryLifecycleObserver(this.tripRepository);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // 🎯 RENDER OPTIMIZATION: Schedule cleanup during idle time
      // Uses post-frame callback with 5s delay to avoid frame drops
      // This ensures cleanup never conflicts with active user interactions
      SchedulerBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(seconds: 5), () {
          tripRepository.cleanupExpiredCache();
          if (kDebugMode) {
            debugPrint('[TripRepository][LIFECYCLE] 🧹 Cleared expired trips on ${state.name}');
          }
        });
      });
    }
  }
}

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});
  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  _TripRepositoryLifecycleObserver? _lifecycleObserver;
  
  @override
  void initState() {
    super.initState();
    
    // Register lifecycle observer for automatic trip cache cleanup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final tripRepo = ref.read(tripRepositoryProvider);
        _lifecycleObserver = _TripRepositoryLifecycleObserver(tripRepo);
        WidgetsBinding.instance.addObserver(_lifecycleObserver!);
        
        if (kDebugMode) {
          debugPrint('[AppRoot] 🔗 Registered TripRepository lifecycle observer');
        }
      }
    });
    
    // Initialize NotificationService with context for deep-link navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final notificationService = ref.read(notificationServiceProvider);
          // Re-initialize with context for proper navigation from background
          notificationService.init(context: context);
          if (kDebugMode) {
            debugPrint('[AppRoot] 🔔 NotificationService context initialized');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[AppRoot] ⚠️ Failed to initialize notification context: $e');
          }
        }
      }
    });
    
    // Precache common marker images to avoid frame jank when markers first appear.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        precacheCommonMarkers(context);
        
        // ✨ NEW OPTIMIZATION: Precache Material Icon glyphs
        IconPrecacheService.instance.warmup(context);
      }
    });

    // Kick off notifications boot initializer (await DAOs then init repo)
    // ignore: unused_result
    ref.read(notificationsBootInitializer);
    
    // 🎯 Initialize geofence notification bridge
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          // Watch the provider to ensure it's initialized
          ref.read(geofenceNotificationBridgeProvider);
          if (kDebugMode) {
            debugPrint('[AppRoot] 🔔 Geofence notification bridge initializing');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[AppRoot] ⚠️ Failed to initialize geofence notifications: $e');
          }
        }
        
        // 🎯 Initialize geofence position feeder
        // This connects VehicleDataRepository position updates to GeofenceMonitor
        try {
          ref.read(geofencePositionFeederProvider);
          if (kDebugMode) {
            debugPrint('[AppRoot] 📍 Geofence position feeder initializing');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[AppRoot] ⚠️ Failed to initialize geofence position feeder: $e');
          }
        }

        // ▶️ Ensure geofence monitor auto-starts for authenticated users
        try {
          ref.read(geofenceAutoMonitorProvider);
          if (kDebugMode) {
            debugPrint('[AppRoot] 🚀 Geofence auto-monitor initializer wired');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[AppRoot] ⚠️ Failed to wire auto-monitor initializer: $e');
          }
        }

        // 🛰 Attach Geofence Health overlay in debug
        if (kDebugMode && _showGeofenceOverlay) {
          try {
            GeofenceHealthOverlay.attach(context);
            debugPrint('[AppRoot] 🛰 Geofence Health overlay attached');
          } catch (e) {
            debugPrint('[AppRoot] ⚠️ Failed to attach Geofence Health overlay: $e');
          }
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rebind to VehicleRepo.onEvent on every rebuild to survive reconnects
    _subscribeToVehicleEvents();
  }

  /// Subscribe to VehicleRepo.onEvent stream with reconnection-awareness.
  /// Cancels any existing subscription and creates a new one to ensure
  /// notifications continue flowing even after WebSocket reconnects.
  void _subscribeToVehicleEvents() {
    // Cancel existing subscription to avoid double-listening
    _eventSub?.cancel();

    final repo = ref.read(vehicleDataRepositoryProvider);
    
    if (kDebugMode) {
      debugPrint('[AppRoot] 🔗 Subscribing to VehicleRepo.onEvent stream');
    }

    _eventSub = repo.onEvent.listen(
      (raw) async {
        try {
          final event = Event.fromJson(raw);
          final notifRepo = await ref.read(notificationsRepositoryProvider.future);
          await notifRepo.addEvent(event);
          if (kDebugMode) {
            debugPrint('[AppRoot] 📩 Forwarded ${event.type} → NotificationsRepository');
          }
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('[AppRoot] ⚠️ Failed to forward WS event: $e');
            debugPrint('[AppRoot] Stack trace: $st');
          }
        }
      },
      onError: (dynamic err, StackTrace st) {
        if (kDebugMode) {
          debugPrint('[AppRoot] ❌ VehicleRepo.onEvent error: $err');
          debugPrint('[AppRoot] Stack trace: $st');
        }
      },
      onDone: () {
        if (kDebugMode) {
          debugPrint('[AppRoot] ⚠️ VehicleRepo stream closed, will rebind on next rebuild');
        }
        // Optionally retry after a short delay
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _subscribeToVehicleEvents();
          }
        });
      },
      cancelOnError: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(
      debugCheckHasDirectionality(context),
      'Directionality missing: AppRoot must be under a MaterialApp/Directionality',
    );
    final router = ref.watch(goRouterProvider);
    final currentLocale = ref.watch(localeProvider);
    
    final app = MaterialApp.router(
        title: 'GPS Tracker',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: router,
        // Localization configuration using generated AppLocalizations
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: currentLocale,
        // No global NotificationToastListener here; pages can add locally
        builder: (context, child) => child ?? const SizedBox.shrink(),
      );

    // Return app directly; debug performance HUD removed globally
    return app;
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    
    // Unregister lifecycle observer
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      if (kDebugMode) {
        debugPrint('[AppRoot] 🔌 Unregistered TripRepository lifecycle observer');
      }
    }
    
    super.dispose();
  }
}
