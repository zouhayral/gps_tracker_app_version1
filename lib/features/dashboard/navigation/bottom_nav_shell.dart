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
    
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        color: const Color(0xFFE2F998),
        padding: const EdgeInsets.only(top: 5),
        child: NavigationBar(
          selectedIndex: currentIndex,
          destinations: [
            NavigationDestination(icon: const Icon(Icons.map), label: t.mapTitle),
            NavigationDestination(icon: const Icon(Icons.alt_route), label: t.tripsTitle),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unreadCount > 0,
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                child: const Icon(Icons.notifications),
              ),
              label: t.notificationsTitle,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings), 
              label: t.settingsTitle,
            ),
          ],
          onDestinationSelected: (i) async {
            debugPrint('[BottomNav] Destination $i selected (current: $currentIndex)');
            
            // If there's a modal route on top (like fullscreen trip map), pop it first
            if (Navigator.of(context).canPop()) {
              debugPrint('[BottomNav] Popping modal route before navigation');
              await Navigator.of(context).maybePop();
              // Wait for navigation animation to complete
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            
            // Check if we're already on the target route
            if ((i == 0 && currentIndex == 0) ||
                (i == 1 && currentIndex == 1) ||
                (i == 2 && currentIndex == 2) ||
                (i == 3 && currentIndex == 3)) {
              debugPrint('[BottomNav] Already on target tab, skipping navigation');
              return; // Already on this tab
            }
            
            switch (i) {
              case 0:
                debugPrint('[BottomNav] Navigating to Map');
                context.safeGo(AppRoutes.map);
              case 1:
                debugPrint('[BottomNav] Navigating to Trips');
                context.safeGo(AppRoutes.trips);
              case 2:
                debugPrint('[BottomNav] Navigating to Alerts');
                context.safeGo(AppRoutes.alerts);
              case 3:
                debugPrint('[BottomNav] Navigating to Settings');
                context.safeGo(AppRoutes.settings);
            }
          },
        ),
      ),
    );
  }
}
