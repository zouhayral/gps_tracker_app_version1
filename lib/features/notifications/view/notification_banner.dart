import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';
import 'package:my_app_gps/core/utils/shared_prefs_holder.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/providers/notification_providers.dart';

/// Bottom, swipe-to-dismiss banner that appears when a new notification event arrives.
///
/// Behavior:
/// - Listens to CustomerEventsMessage from the WebSocket provider
/// - Shows a bottom-aligned banner when notifications are enabled
/// - Dismissible horizontally; stays hidden until a new event arrives
/// - Tapping "View" navigates to the Alerts page
class NotificationBanner extends ConsumerStatefulWidget {
  const NotificationBanner({super.key});

  @override
  ConsumerState<NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends ConsumerState<NotificationBanner> {
  bool _showBanner = false;
  Event? _event;
  Offset _slideOffset = const Offset(0, 0.2);
  double _opacity = 0;
  StreamSubscription<Event>? _sub;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    // Listen to enriched events from NotificationsRepository
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Attach once to the stream - await repository initialization
      final repo = await ref.read(notificationsRepositoryProvider.future);
      _sub = repo.watchNewEvents().listen(_handleEvent);
    });
  }

  void _handleEvent(Event e) {
    // Respect global notifications toggle (controls banner only)
    final enabled = !SharedPrefsHolder.isInitialized ||
        (SharedPrefsHolder.instance.getBool('notifications_enabled') ?? true);
    if (!enabled) {
      debugPrint('[NotificationBanner] 🚫 Banner suppressed (toggle OFF)');
      return;
    }

    setState(() {
      _event = e;
      _showBanner = true;
      _slideOffset = const Offset(0, 0.2);
      _opacity = 0.0;
    });
    // Animate in
    Future.microtask(() {
      if (!mounted) return;
      setState(() {
        _slideOffset = Offset.zero;
        _opacity = 1.0;
      });
    });
    final name = e.deviceName ?? 'Device ${e.deviceId}';
    final pr = _priorityLabel(e);
    debugPrint('[NotificationBanner] 🪧 Showing banner for $name ($pr)');
  }

  void _onViewPressed() {
    if (!mounted) return;
    context.safeGo(AppRoutes.alerts);
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBanner || _event == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final e = _event!;
    final icon = e.icon;
    final name = e.deviceName ?? 'Device ${e.deviceId}';
    final message = e.message ?? e.formattedMessage;
    final (chipLabel, chipColor) = _priorityChip(e);

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedSlide(
        duration: Duration(milliseconds: _exiting ? 250 : 350),
        curve: _exiting ? Curves.easeIn : Curves.easeOut,
        offset: _slideOffset,
        child: AnimatedOpacity(
          // Exit faster for snappier dismissal
          duration: Duration(milliseconds: _exiting ? 250 : 350),
          opacity: _opacity,
          child: Dismissible(
            key: const ValueKey('notification-banner'),
            onDismissed: (_) {
              setState(() {
                _exiting = true;
                _opacity = 0.0;
                _slideOffset = const Offset(0, 0.2);
              });
              Future.delayed(const Duration(milliseconds: 250), () {
                if (!mounted) return;
                setState(() {
                  _showBanner = false;
                  _exiting = false;
                });
              });
            },
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 6,
                    spreadRadius: 0.5,
                    offset: Offset(0, -1),
                    color: Colors.black26,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(icon, color: e.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4,),
                              decoration: BoxDecoration(
                                color: chipColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                chipLabel,
                                style: TextStyle(
                                    color: chipColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.8),),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _onViewPressed,
                    child: const Text('New'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // Helpers
  (String, Color) _priorityChip(Event e) {
    final pAttr = e.attributes['priority'];
    final p = (pAttr is String)
        ? pAttr.toLowerCase()
        : pAttr?.toString().toLowerCase();
    switch (p) {
      case 'high':
        return ('High', const Color(0xFFFF383C));
      case 'medium':
        return ('Medium', const Color(0xFFFFBD28));
      default:
        return ('Low', const Color(0xFF4CAF50));
    }
  }

  String _priorityLabel(Event e) => _priorityChip(e).$1;
}

