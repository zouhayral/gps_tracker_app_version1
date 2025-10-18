import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Connectivity status manager backed by connectivity_plus.
///
/// Responsibilities:
/// - Listen for connectivity changes (Wi‑Fi, mobile, none, etc.)
/// - Maintain a [ValueNotifier] that indicates offline/online state
/// - Provide a quick synchronous getter [isOfflineNow]
///
/// Usage:
/// ```dart
/// final manager = ConnectivityManager();
/// await manager.initialize();
/// // Listen in UI
/// ValueListenableBuilder<bool>(
///   valueListenable: manager.isOffline,
///   builder: (_, offline, __) => Text(offline ? 'Offline' : 'Online'),
/// );
/// ```
class ConnectivityManager {
  ConnectivityManager({ConnectivitySource? source})
      : _source = source ?? const _DefaultConnectivitySource();

  final ConnectivitySource _source;

  /// Notifier that is true when there is no active network connection.
  ///
  /// Emits updates whenever connectivity changes.
  final ValueNotifier<bool> isOffline = ValueNotifier<bool>(false);

  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Initialize the manager: queries initial connectivity and subscribes to updates.
  Future<void> initialize() async {
    // Set initial state from a one-shot check.
  final initial = await _source.checkConnectivity();
  isOffline.value = _isOfflineFromList(initial);

    // Listen to subsequent changes.
    _sub = _source.onConnectivityChanged.listen((results) {
      final next = _isOfflineFromList(results);
      if (next != isOffline.value) {
        isOffline.value = next;
      }
    });
  }

  /// Dispose the internal subscription and notifier.
  void dispose() {
    _sub?.cancel();
    isOffline.dispose();
  }

  /// Synchronous snapshot of the current offline state.
  bool get isOfflineNow => isOffline.value;

  // Map connectivity result to offline/online flag.
  bool _isOfflineFromList(List<ConnectivityResult> results) {
    // Offline if there are no active transports or if all report `none`.
    // Any non-`none` transport (wifi/mobile/ethernet/vpn/etc.) counts as online.
    if (results.isEmpty) return true;
    return results.every((r) => r == ConnectivityResult.none);
  }
}

/// Abstraction layer over connectivity_plus for easier testing.
abstract class ConnectivitySource {
  const ConnectivitySource();

  Future<List<ConnectivityResult>> checkConnectivity();
  Stream<List<ConnectivityResult>> get onConnectivityChanged;
}

/// Default implementation that forwards to connectivity_plus.
class _DefaultConnectivitySource implements ConnectivitySource {
  const _DefaultConnectivitySource();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() {
    return Connectivity().checkConnectivity();
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Connectivity().onConnectivityChanged;
}
