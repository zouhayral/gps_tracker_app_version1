import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_app_gps/features/auth/controller/auth_notifier.dart';
import 'package:my_app_gps/features/auth/controller/auth_state.dart';
import 'package:my_app_gps/features/auth/presentation/login_page.dart';
import 'package:my_app_gps/features/dashboard/navigation/bottom_nav_shell.dart';
import 'package:my_app_gps/features/geofencing/ui/geofence_detail_page.dart';
import 'package:my_app_gps/features/geofencing/ui/geofence_form_page.dart';
import 'package:my_app_gps/features/geofencing/ui/geofence_list_page.dart';
import 'package:my_app_gps/features/geofencing/ui/geofence_settings_page.dart';
import 'package:my_app_gps/features/map/view/map_page.dart';
import 'package:my_app_gps/features/notifications/view/notifications_page.dart';
import 'package:my_app_gps/features/settings/view/settings_page.dart';
import 'package:my_app_gps/features/telemetry/telemetry_history_page.dart';
import 'package:my_app_gps/features/trips/view/trips_page.dart';
import 'package:my_app_gps/features/analytics/view/analytics_page.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';

// Global navigator key for background navigation (e.g., from notifications)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Route names / paths constants
class AppRoutes {
  static const login = '/login';
  static const map = '/map';
  static const trips = '/trips';
  static const alerts = '/alerts';
  static const settings = '/settings';
  
  /// Route for the analytics reports and statistics page.
  static const analytics = '/analytics';
  
  static const telemetryHistory = '/telemetry-history';
  static const geofences = '/geofences';
  static const geofenceDetail = '/geofences';
}

// Riverpod provider exposing a configured GoRouter. It rebuilds when auth changes.
// Optimized with .select() to limit rebuilds to auth status only
final goRouterProvider = Provider<GoRouter>((ref) {
  final isLoggedIn = ref.watch(
    authNotifierProvider.select((s) => s is AuthAuthenticated),
  );

  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: AppRoutes.map,
    // Error boundary: redirect to map page on any navigation error
    errorBuilder: (context, state) {
      debugPrint('[Router] ❌ Navigation error: ${state.error}');
      debugPrint('[Router] 🔄 Redirecting to map page');
      return const MapPage();
    },
    redirect: (context, state) {
      final loggingIn = state.fullPath == AppRoutes.login;
      if (!isLoggedIn && !loggingIn) return AppRoutes.login;
      if (isLoggedIn && loggingIn) return AppRoutes.map;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      // Standalone route for telemetry history page (push from any context)
      GoRoute(
        path: AppRoutes.telemetryHistory,
        name: 'telemetry-history',
        builder: (context, state) {
          final qp = state.uri.queryParameters;
          final idParam = qp['deviceId'];
          final deviceId = int.tryParse(idParam ?? '');
          if (deviceId == null) {
            return const Scaffold(
              body: Center(child: Text('Missing or invalid deviceId')),
            );
          }
          return TelemetryHistoryPage(deviceId: deviceId);
        },
      ),
      // Geofence list route (standalone, accessible from settings)
      GoRoute(
        path: AppRoutes.geofences,
        name: 'geofences',
        builder: (context, state) => const GeofenceListPage(),
      ),
      // Analytics route (standalone, accessible from settings)
      GoRoute(
        path: AppRoutes.analytics,
        name: 'analytics',
        builder: (context, state) {
          AppLogger.debug('[Router] Navigated to AnalyticsPage');
          return const AnalyticsPage();
        },
      ),
      // Geofence settings route (accessible from geofence list)
      GoRoute(
        path: '${AppRoutes.geofences}/settings',
        name: 'geofence-settings',
        builder: (context, state) => const GeofenceSettingsPage(),
      ),
      // Geofence create route (must come BEFORE detail route to match first)
      GoRoute(
        path: '${AppRoutes.geofences}/create',
        name: 'geofence-create',
        builder: (context, state) => const GeofenceFormPage(
          mode: GeofenceFormMode.create,
        ),
      ),
      // Geofence edit route
      GoRoute(
        path: '${AppRoutes.geofences}/:id/edit',
        name: 'geofence-edit',
        builder: (context, state) {
          final id = state.pathParameters['id'];
          if (id == null || id.isEmpty) {
            return const Scaffold(
              body: Center(child: Text('Missing geofence ID')),
            );
          }
          return GeofenceFormPage(
            mode: GeofenceFormMode.edit,
            geofenceId: id,
          );
        },
      ),
      // Geofence detail route for deep-linking from notifications
      GoRoute(
        path: '${AppRoutes.geofenceDetail}/:id',
        name: 'geofence-detail',
        builder: (context, state) {
          final id = state.pathParameters['id'];
          if (id == null || id.isEmpty) {
            return const Scaffold(
              body: Center(child: Text('Missing geofence ID')),
            );
          }
          return GeofenceDetailPage(geofenceId: id);
        },
      ),
      // Shell containing bottom navigation destinations
      ShellRoute(
        builder: (context, state, child) => BottomNavShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.map,
            name: 'map',
            pageBuilder: (context, state) {
              final qp = state.uri.queryParameters;
              Set<int>? preselected;
              final deviceParam = qp['device'];
              if (deviceParam != null && deviceParam.isNotEmpty) {
                final parts = deviceParam.split(',');
                preselected = {
                  for (final p in parts)
                    if (int.tryParse(p.trim()) != null) int.parse(p.trim()),
                };
                if (preselected.isEmpty) preselected = null; // ignore invalid
              }
              return NoTransitionPage(
                child: MapPage(preselectedIds: preselected),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.trips,
            name: 'trips',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: TripsPage()),
          ),
          GoRoute(
            path: AppRoutes.alerts,
            name: 'alerts',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: NotificationsPage()),
          ),
          GoRoute(
            path: AppRoutes.settings,
            name: 'settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsPage()),
          ),
        ],
      ),
    ],
    observers: [routeObserver],
  );
});

// Simple RouteObserver for analytics / logging hooks.
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();
