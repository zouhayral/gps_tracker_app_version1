import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/controllers/connectivity_coordinator.dart';
import 'package:my_app_gps/providers/connectivity_provider.dart';

/// Debounced offline banner that prevents flicker
///
/// Shows "No network connection" banner only after sustained offline state
/// (3-5 seconds) and hides after 2 consecutive successful pings.
///
/// This prevents annoying banner flicker during temporary signal drops.
class OfflineBanner extends ConsumerStatefulWidget {
  /// Duration offline before showing banner
  final Duration showDelay;

  /// Number of consecutive successful pings before hiding
  final int hideThreshold;

  const OfflineBanner({
    super.key,
    this.showDelay = const Duration(seconds: 4),
    this.hideThreshold = 2,
  });

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner>
    with SingleTickerProviderStateMixin {
  bool _showBanner = false;
  Timer? _debounceTimer;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _updateBannerState(bool shouldShow) {
    if (shouldShow && !_showBanner) {
      setState(() => _showBanner = true);
      _animationController.forward();
    } else if (!shouldShow && _showBanner) {
      _animationController.reverse().then((_) {
        if (mounted) {
          setState(() => _showBanner = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(connectivityProvider, (previous, next) {
      // Cancel any pending timer
      _debounceTimer?.cancel();

      if (next.isOffline) {
        // Start debounce timer for showing banner
        _debounceTimer = Timer(widget.showDelay, () {
          if (mounted) {
            final currentState = ref.read(connectivityProvider);
            if (currentState.isOffline) {
              _updateBannerState(true);
            }
          }
        });
      } else {
        // Hide immediately after reaching success threshold
        if (next.consecutiveSuccessfulPings >= widget.hideThreshold) {
          _updateBannerState(false);
        }
      }
    });

    if (!_showBanner) {
      return const SizedBox.shrink();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: Material(
        color: Colors.red.shade700,
        elevation: 4,
        child: SafeArea(
          bottom: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_off,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No network connection',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getBannerSubtitle(ref.read(connectivityProvider)),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: () {
                    ref.read(connectivityProvider.notifier).forceCheck();
                  },
                  tooltip: 'Retry connection',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getBannerSubtitle(ConnectivityState state) {
    if (!state.networkAvailable) {
      return 'Showing cached data only';
    }
    if (state.hasNetworkButNoBackend) {
      return 'Server unreachable – showing cached data';
    }
    return 'Showing cached data';
  }
}
