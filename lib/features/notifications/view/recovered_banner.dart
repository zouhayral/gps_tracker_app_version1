import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';

/// Bottom, swipe-to-dismiss banner that appears after reconnect backfill,
/// showing how many notifications were recovered.
class RecoveredEventsBanner extends ConsumerStatefulWidget {
  const RecoveredEventsBanner({super.key});

  @override
  ConsumerState<RecoveredEventsBanner> createState() =>
      _RecoveredEventsBannerState();
}

class _RecoveredEventsBannerState extends ConsumerState<RecoveredEventsBanner> {
  bool _show = false;
  int _count = 0;
  double _opacity = 0;
  Offset _offset = const Offset(0, 0.2);
  bool _exiting = false;
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final repo = ref.read(vehicleDataRepositoryProvider);
      _sub = repo.onRecoveredEvents.listen(_onRecovered);
    });
  }

  void _onRecovered(int count) {
    if (count <= 0) return;
    setState(() {
      _count = count;
      _show = true;
      _opacity = 0.0;
      _offset = const Offset(0, 0.2);
      _exiting = false;
    });
    // Animate in
    Future.microtask(() {
      if (!mounted) return;
      setState(() {
        _opacity = 1.0;
        _offset = Offset.zero;
      });
    });

    // Auto-dismiss after a delay
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted || !_show) return;
      setState(() {
        _exiting = true;
        _opacity = 0.0;
        _offset = const Offset(0, 0.2);
      });
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        setState(() {
          _show = false;
          _exiting = false;
        });
      });
    });
  }

  void _onView() {
    if (!mounted) return;
    context.go(AppRoutes.alerts);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show || _count <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedSlide(
        duration: Duration(milliseconds: _exiting ? 250 : 350),
        curve: _exiting ? Curves.easeIn : Curves.easeOut,
        offset: _offset,
        child: AnimatedOpacity(
          duration: Duration(milliseconds: _exiting ? 250 : 350),
          opacity: _opacity,
          child: Dismissible(
            key: const ValueKey('recovered-events-banner'),
            onDismissed: (_) {
              setState(() {
                _exiting = true;
                _opacity = 0.0;
                _offset = const Offset(0, 0.2);
              });
              Future.delayed(const Duration(milliseconds: 250), () {
                if (!mounted) return;
                setState(() {
                  _show = false;
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
                  const Icon(Icons.cloud_download, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recovered $_count notification${_count == 1 ? '' : 's'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _onView,
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
}
