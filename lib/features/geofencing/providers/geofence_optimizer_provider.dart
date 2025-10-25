import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/geofence_optimizer_state.dart';
import '../service/geofence_optimizer_service.dart';

/// Provider for optimizer state stream
///
/// Emits optimizer state updates every 5 seconds for UI display
final optimizerStateStreamProvider = StreamProvider<GeofenceOptimizerState>((ref) async* {
  final service = ref.watch(geofenceOptimizerServiceProvider);
  
  // Emit initial state
  yield service.state;
  
  // Periodic updates every 5 seconds
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 5));
    yield service.state;
  }
});

/// Provider for current optimizer state
///
/// Returns the latest state snapshot
final optimizerStateProvider = Provider<GeofenceOptimizerState>((ref) {
  final asyncState = ref.watch(optimizerStateStreamProvider);
  return asyncState.maybeWhen(
    data: (state) => state,
    orElse: () => const GeofenceOptimizerState(),
  );
});

/// Provider for checking if optimizer is active
final isOptimizerActiveProvider = Provider<bool>((ref) {
  return ref.watch(optimizerStateProvider).isActive;
});

/// Provider for checking if currently throttling
final isThrottlingProvider = Provider<bool>((ref) {
  return ref.watch(optimizerStateProvider).isThrottling;
});

/// Provider for current optimization mode
final optimizationModeProvider = Provider<OptimizationMode>((ref) {
  return ref.watch(optimizerStateProvider).mode;
});

/// Provider for battery level
final batteryLevelProvider = Provider<int>((ref) {
  return ref.watch(optimizerStateProvider).batteryLevel;
});

/// Provider for battery status description
final batteryStatusProvider = Provider<String>((ref) {
  return ref.watch(optimizerStateProvider).batteryStatus;
});

/// Provider for motion status description
final motionStatusProvider = Provider<String>((ref) {
  return ref.watch(optimizerStateProvider).motionStatus;
});

/// Provider for current interval in seconds
final currentIntervalProvider = Provider<int>((ref) {
  return ref.watch(optimizerStateProvider).currentIntervalSeconds;
});

/// Provider for optimizer status description
final optimizerStatusProvider = Provider<String>((ref) {
  return ref.watch(optimizerStateProvider).description;
});

/// Provider for diagnostics map
final optimizerDiagnosticsProvider = Provider<Map<String, dynamic>>((ref) {
  return ref.watch(optimizerStateProvider).diagnostics;
});

/// Provider for battery savings percentage
final batterySavingsPercentProvider = Provider<double>((ref) {
  return ref.watch(optimizerStateProvider).batterySavingsPercent;
});

/// State notifier for managing optimizer lifecycle
class OptimizerNotifier extends StateNotifier<AsyncValue<void>> {
  final GeofenceOptimizerService _service;

  OptimizerNotifier(this._service) : super(const AsyncValue.data(null));

  /// Start the optimizer
  Future<void> start() async {
    state = const AsyncValue.loading();
    
    try {
      await _service.start();
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  /// Stop the optimizer
  Future<void> stop() async {
    state = const AsyncValue.loading();
    
    try {
      await _service.stop();
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  /// Force battery check
  Future<void> forceBatteryCheck() async {
    await _service.forceBatteryCheck();
  }

  /// Force motion check
  void forceMotionCheck() {
    _service.forceMotionCheck();
  }

  /// Reset statistics
  void resetStatistics() {
    _service.resetStatistics();
  }

  /// Get current metrics
  Map<String, dynamic> get metrics => _service.metrics;
}

/// Provider for optimizer lifecycle management
final optimizerNotifierProvider =
    StateNotifierProvider<OptimizerNotifier, AsyncValue<void>>((ref) {
  final service = ref.watch(geofenceOptimizerServiceProvider);
  return OptimizerNotifier(service);
});

/// Convenience provider for optimizer actions
final optimizerActionsProvider = Provider<OptimizerActions>((ref) {
  return OptimizerActions(ref);
});

/// Helper class for optimizer actions
class OptimizerActions {
  final Ref _ref;

  OptimizerActions(this._ref);

  /// Start the optimizer
  Future<void> start() async {
    await _ref.read(optimizerNotifierProvider.notifier).start();
  }

  /// Stop the optimizer
  Future<void> stop() async {
    await _ref.read(optimizerNotifierProvider.notifier).stop();
  }

  /// Toggle optimizer on/off
  Future<void> toggle() async {
    final isActive = _ref.read(isOptimizerActiveProvider);
    if (isActive) {
      await stop();
    } else {
      await start();
    }
  }

  /// Force battery check
  Future<void> checkBattery() async {
    await _ref.read(optimizerNotifierProvider.notifier).forceBatteryCheck();
  }

  /// Force motion check
  void checkMotion() {
    _ref.read(optimizerNotifierProvider.notifier).forceMotionCheck();
  }

  /// Reset statistics
  void resetStats() {
    _ref.read(optimizerNotifierProvider.notifier).resetStatistics();
  }

  /// Get current metrics
  Map<String, dynamic> get metrics {
    return _ref.read(optimizerNotifierProvider.notifier).metrics;
  }

  /// Check if position should be evaluated (for throttling)
  bool shouldEvaluate(int deviceId) {
    final service = _ref.read(geofenceOptimizerServiceProvider);
    return service.shouldEvaluatePosition(deviceId);
  }

  // State getters
  bool get isActive => _ref.read(isOptimizerActiveProvider);
  bool get isThrottling => _ref.read(isThrottlingProvider);
  OptimizationMode get mode => _ref.read(optimizationModeProvider);
  int get batteryLevel => _ref.read(batteryLevelProvider);
  String get batteryStatus => _ref.read(batteryStatusProvider);
  String get motionStatus => _ref.read(motionStatusProvider);
  int get currentInterval => _ref.read(currentIntervalProvider);
  String get status => _ref.read(optimizerStatusProvider);
  Map<String, dynamic> get diagnostics => _ref.read(optimizerDiagnosticsProvider);
  double get savingsPercent => _ref.read(batterySavingsPercentProvider);
}
