import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reconnection status lifecycle
enum ReconnectPhase {
  idle,
  scheduled,
  attempting,
  connected,
  failed,
  exhausted,
}

class ReconnectState {
  final ReconnectPhase phase;
  final int attempt;
  final String? reason;
  final DateTime timestamp;

  ReconnectState({
    required this.phase,
    required this.attempt,
    this.reason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'ReconnectState(phase=$phase, attempt=$attempt, reason=$reason)';
}

/// Coordinates all WebSocket reconnections across the app.
///
/// Guarantees:
/// - Only one reconnection attempt runs at a time (global gate)
/// - Exponential backoff: delay = 2^attempt seconds (attempt: 1..5)
/// - Max attempts capped at 5, then emits `exhausted`
/// - Resubscribes registered subscribers exactly once on success
///
/// Usage:
/// - Set connector: `ReconnectionCoordinator.instance.setConnector(() async => await socketConnectOnce())`
/// - Trigger on loss: `ReconnectionCoordinator.instance.trigger('onDone')`
/// - Register resubscriptions: `registerSubscription('notifications', () async { ... })`
class ReconnectionCoordinator {
  ReconnectionCoordinator._();
  static final ReconnectionCoordinator instance = ReconnectionCoordinator._();

  // Optional Riverpod provider
  static final provider = Provider<ReconnectionCoordinator>((_) => instance);

  // Connector performs a single connection attempt and returns true on success
  Future<bool> Function()? _connector;

  // Subscriptions to run after a successful reconnection
  final Map<String, Future<void> Function()> _subscriptions = {};

  // State stream for diagnostics
  final _stateCtrl = StreamController<ReconnectState>.broadcast();
  Stream<ReconnectState> get states => _stateCtrl.stream;

  // Concurrency guards
  bool _isReconnecting = false;
  int _attempt = 0;
  final int _maxAttempts = 5;
  Completer<void>? _inFlight; // allows await of current cycle

  // Public API
  void setConnector(Future<bool> Function() connector) {
    _connector = connector;
  }

  void registerSubscription(String key, Future<void> Function() subscribe) {
    _subscriptions[key] = subscribe;
  }

  void unregisterSubscription(String key) {
    _subscriptions.remove(key);
  }

  /// Notify that a connection has been established successfully outside
  /// of the coordinator (optional). This resets attempts and runs subscriptions.
  Future<void> onConnected() async {
    _attempt = 0;
    _isReconnecting = false;
    _stateCtrl.add(ReconnectState(phase: ReconnectPhase.connected, attempt: 0));
    await _runSubscriptions();
  }

  /// Trigger a reconnection cycle if not already running.
  Future<void> trigger(String reason) async {
    if (_connector == null) {
      if (kDebugMode) debugPrint('[ReconnectionCoordinator] No connector set; ignoring trigger ($reason)');
      return;
    }

    // Coalesce multiple triggers
    if (_isReconnecting) {
      if (kDebugMode) debugPrint('[ReconnectionCoordinator] Reconnect already in progress; coalescing ($reason)');
      return _inFlight?.future;
    }

    _isReconnecting = true;
    _inFlight = Completer<void>();

    try {
      for (_attempt = 1; _attempt <= _maxAttempts; _attempt++) {
        // Backoff delay: 2^attempt seconds
        final seconds = math.pow(2, _attempt).toInt();
        _stateCtrl.add(ReconnectState(phase: ReconnectPhase.scheduled, attempt: _attempt, reason: reason));
        await Future<void>.delayed(Duration(seconds: seconds));

        _stateCtrl.add(ReconnectState(phase: ReconnectPhase.attempting, attempt: _attempt, reason: reason));
        final ok = await _connector!.call();
        if (ok) {
          // Success: reset and resubscribe
          await onConnected();
          _inFlight?.complete();
          _inFlight = null;
          return;
        }
      }

      // Exhausted
      _stateCtrl.add(ReconnectState(phase: ReconnectPhase.exhausted, attempt: _attempt - 1, reason: reason));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[ReconnectionCoordinator] Reconnect failed: $e');
        debugPrint('$st');
      }
      _stateCtrl.add(ReconnectState(phase: ReconnectPhase.failed, attempt: _attempt, reason: '$e'));
    } finally {
      _isReconnecting = false;
      _inFlight?.complete();
      _inFlight = null;
    }
  }

  Future<void> _runSubscriptions() async {
    if (_subscriptions.isEmpty) return;
    // Run sequentially to avoid bursts
    for (final entry in _subscriptions.entries) {
      try {
        await entry.value.call();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ReconnectionCoordinator] Subscription failed for ${entry.key}: $e');
        }
      }
    }
  }
}
