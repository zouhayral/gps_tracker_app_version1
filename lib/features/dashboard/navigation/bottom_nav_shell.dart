import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_app_gps/app/app_router.dart';
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
        color: const Color(0xFFE9F9B9),
        padding: const EdgeInsets.only(top: 5),
        child: NavigationBar(
          selectedIndex: currentIndex,
          destinations: [
            const NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
            const NavigationDestination(icon: Icon(Icons.alt_route), label: 'Trips'),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unreadCount > 0,
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                child: const Icon(Icons.notifications),
              ),
              label: 'Alerts',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings), 
              label: 'Settings',
            ),
          ],
          onDestinationSelected: (i) {
            switch (i) {
              case 0:
                context.go(AppRoutes.map);
              case 1:
                context.go(AppRoutes.trips);
              case 2:
                context.go(AppRoutes.alerts);
              case 3:
                context.go(AppRoutes.settings);
            }
          },
        ),
      ),
    );
  }
}
