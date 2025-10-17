import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_app_gps/features/auth/controller/auth_notifier.dart';
import 'package:my_app_gps/features/auth/controller/auth_state.dart';
import 'package:my_app_gps/features/auth/presentation/login_page.dart';
import 'package:my_app_gps/features/dashboard/navigation/bottom_nav_shell.dart';
import 'package:my_app_gps/features/map/view/map_page.dart';
import 'package:my_app_gps/features/notifications/view/notifications_page.dart';
import 'package:my_app_gps/features/settings/view/settings_page.dart';
import 'package:my_app_gps/features/trips/view/trips_page.dart';

// Route names / paths constants
class AppRoutes {
  static const login = '/login';
  static const map = '/map';
  static const trips = '/trips';
  static const alerts = '/alerts';
  static const settings = '/settings';
}

// Riverpod provider exposing a configured GoRouter. It rebuilds when auth changes.
final goRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: AppRoutes.map,
    redirect: (context, state) {
      final isLoggedIn = auth is AuthAuthenticated;
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
                    if (int.tryParse(p.trim()) != null) int.parse(p.trim())
                };
                if (preselected.isEmpty) preselected = null; // ignore invalid
              }
              return NoTransitionPage(
                  child: MapPage(preselectedIds: preselected));
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
