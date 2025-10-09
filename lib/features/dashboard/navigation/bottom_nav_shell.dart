import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app.dart/app_router.dart';

class BottomNavShell extends StatefulWidget {
  const BottomNavShell({super.key, required this.child});
  final Widget child;
  @override
  State<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends State<BottomNavShell> {
  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    int currentIndex = 0;
    if (location.startsWith(AppRoutes.trips)) currentIndex = 1;
    else if (location.startsWith(AppRoutes.alerts)) currentIndex = 2;
    else if (location.startsWith(AppRoutes.settings)) currentIndex = 3;
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        color: const Color(0xFFE9F9B9),
        padding: const EdgeInsets.only(top: 5),
        child: NavigationBar(
          selectedIndex: currentIndex,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
            NavigationDestination(icon: Icon(Icons.alt_route), label: 'Trips'),
            NavigationDestination(icon: Icon(Icons.notifications), label: 'Alerts'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
          onDestinationSelected: (i) {
            switch (i) {
              case 0: context.go(AppRoutes.map); break;
              case 1: context.go(AppRoutes.trips); break;
              case 2: context.go(AppRoutes.alerts); break;
              case 3: context.go(AppRoutes.settings); break;
            }
          },
        ),
      ),
    );
  }
}
