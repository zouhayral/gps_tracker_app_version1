import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/core/debug/rebuild_counter_overlay.dart';
import 'package:my_app_gps/features/map/view/marker_assets.dart';
import 'package:my_app_gps/features/notifications/view/notification_toast.dart';
import 'package:my_app_gps/theme/app_theme.dart';

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});
  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  @override
  void initState() {
    super.initState();
    // Precache common marker images to avoid frame jank when markers first appear.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        precacheCommonMarkers(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    assert(
      debugCheckHasDirectionality(context),
      'Directionality missing: AppRoot must be under a MaterialApp/Directionality',
    );
    final router = ref.watch(goRouterProvider);
    return RebuildCounterOverlay(
      child: MaterialApp.router(
        title: 'GPS Tracker',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: router,
        // Ensure NotificationToastListener has a context under MaterialApp
        // so it can access the ScaffoldMessenger/Scaffold safely.
        builder: (context, child) => NotificationToastListener(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
