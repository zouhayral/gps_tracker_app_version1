import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/features/debug/dev_diagnostics_controller.dart';
import 'package:my_app_gps/features/debug/dev_diagnostics_overlay.dart';
import 'package:my_app_gps/features/map/view/marker_assets.dart';
import 'package:my_app_gps/providers/notification_providers.dart';
import 'package:my_app_gps/theme/app_theme.dart';

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});
  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  @override
  void initState() {
    super.initState();
    // Precache common marker images to avoid frame jank when markers first appear.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        precacheCommonMarkers(context);
      }
    });

    // Kick off notifications boot initializer (await DAOs then init repo)
    // ignore: unused_result
    ref.read(notificationsBootInitializer);
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
          await ref.read(notificationsRepositoryProvider).addEvent(event);
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
    final showOverlay = ref.watch(showDiagnosticsProvider);
    final app = MaterialApp.router(
        title: 'GPS Tracker',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: router,
        // No global NotificationToastListener here; pages can add locally
        builder: (context, child) => child ?? const SizedBox.shrink(),
      );

    final withOverlay = kDebugMode && showOverlay
        ? DevDiagnosticsOverlay(child: app)
        : app;

    return Stack(
      children: [
        withOverlay,
        if (kDebugMode)
          Positioned(
            top: 0,
            right: 0,
            width: 60,
            height: 60,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: () {
                final notifier = ref.read(showDiagnosticsProvider.notifier);
                notifier.state = !notifier.state;
              },
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
