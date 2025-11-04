import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';
import 'package:my_app_gps/providers/notification_providers.dart';

class BottomNavShell extends ConsumerStatefulWidget {
  const BottomNavShell({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends ConsumerState<BottomNavShell> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final location = GoRouterState.of(context).uri.toString();
    var currentIndex = 0;
    if (location.startsWith(AppRoutes.trips)) {
      currentIndex = 1;
    } else if (location.startsWith(AppRoutes.alerts)) {
      currentIndex = 2;
    } else if (location.startsWith(AppRoutes.settings)) {
      currentIndex = 3;
    }
    
    // Watch unread count for badge
    final unreadCount = ref.watch(unreadCountProvider);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return Scaffold(
      body: widget.child,
      extendBody: true,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 16,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDarkMode ? 0.5 : 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: NavigationBar(
              selectedIndex: currentIndex,
              height: 70,
              elevation: 0,
              backgroundColor: isDarkMode 
                  ? theme.colorScheme.surface
                  : Colors.white,
              indicatorColor: theme.colorScheme.primaryContainer,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              animationDuration: const Duration(milliseconds: 400),
              destinations: [
              NavigationDestination(
                icon: Icon(
                  Icons.map_outlined,
                  color: currentIndex == 0 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                selectedIcon: Icon(
                  Icons.map,
                  color: theme.colorScheme.primary,
                ),
                label: t.mapTitle,
              ),
              NavigationDestination(
                icon: Icon(
                  Icons.route_outlined,
                  color: currentIndex == 1 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                selectedIcon: Icon(
                  Icons.route,
                  color: theme.colorScheme.primary,
                ),
                label: t.tripsTitle,
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unreadCount > 0,
                  label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                  backgroundColor: Colors.red,
                  textColor: Colors.white,
                  child: Icon(
                    Icons.notifications_outlined,
                    color: currentIndex == 2 
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                selectedIcon: Badge(
                  isLabelVisible: unreadCount > 0,
                  label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                  backgroundColor: Colors.red,
                  textColor: Colors.white,
                  child: Icon(
                    Icons.notifications,
                    color: theme.colorScheme.primary,
                  ),
                ),
                label: t.notificationsTitle,
              ),
              NavigationDestination(
                icon: Icon(
                  Icons.settings_outlined,
                  color: currentIndex == 3 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                selectedIcon: Icon(
                  Icons.settings,
                  color: theme.colorScheme.primary,
                ),
                label: t.settingsTitle,
              ),
            ],
            onDestinationSelected: (i) {
              // If there's a modal route on top (like fullscreen trip map), pop it first
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
              
              switch (i) {
                case 0:
                  context.safeGo(AppRoutes.map);
                case 1:
                  context.safeGo(AppRoutes.trips);
                case 2:
                  context.safeGo(AppRoutes.alerts);
                case 3:
                  context.safeGo(AppRoutes.settings);
              }
            },
          ),
        ),
        ),
      ),
    );
  }
}
