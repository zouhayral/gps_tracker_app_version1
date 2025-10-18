/// Riverpod provider for prefetch orchestration
///
/// Manages prefetch state, integrates with connectivity coordinator,
/// and provides UI-accessible prefetch controls.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_app_gps/controllers/connectivity_coordinator.dart';
import 'package:my_app_gps/prefetch/prefetch_orchestrator.dart';
import 'package:my_app_gps/prefetch/prefetch_profile.dart';
import 'package:my_app_gps/prefetch/prefetch_progress.dart';
import 'package:my_app_gps/providers/connectivity_provider.dart';

/// Provider for prefetch orchestrator instance
final prefetchOrchestratorProvider = Provider<PrefetchOrchestrator>((ref) {
  final orchestrator = PrefetchOrchestrator();

  // Auto-pause/resume based on connectivity
  ref.listen<ConnectivityState>(connectivityProvider, (previous, next) {
    if (previous != null && previous.isOnline && next.isOffline) {
      // Went offline → pause prefetch
      orchestrator.pause();
    } else if (previous != null && previous.isOffline && next.isOnline) {
      // Came online → resume prefetch
      orchestrator.resume();
    }
  });

  ref.onDispose(() {
    orchestrator.dispose();
  });

  return orchestrator;
});

/// Provider for prefetch progress stream
final prefetchProgressProvider =
    StreamProvider.autoDispose<PrefetchProgress>((ref) {
  final orchestrator = ref.watch(prefetchOrchestratorProvider);
  return orchestrator.progressStream;
});

/// Provider for current prefetch progress (synchronous access)
final currentPrefetchProgressProvider =
    Provider.autoDispose<PrefetchProgress>((ref) {
  final asyncProgress = ref.watch(prefetchProgressProvider);
  return asyncProgress.when(
    data: (progress) => progress,
    loading: () => const PrefetchProgress.idle(),
    error: (_, __) => const PrefetchProgress.idle(),
  );
});

/// Provider for prefetch settings (profile, enabled state)
final prefetchSettingsProvider =
    StateNotifierProvider<PrefetchSettingsNotifier, PrefetchSettings>((ref) {
  return PrefetchSettingsNotifier();
});

/// Prefetch settings state
class PrefetchSettings {
  final bool enabled;
  final PrefetchProfile selectedProfile;

  const PrefetchSettings({
    this.enabled = false,
    this.selectedProfile = PrefetchProfile.light,
  });

  PrefetchSettings copyWith({
    bool? enabled,
    PrefetchProfile? selectedProfile,
  }) {
    return PrefetchSettings(
      enabled: enabled ?? this.enabled,
      selectedProfile: selectedProfile ?? this.selectedProfile,
    );
  }
}

/// Settings notifier with persistence
class PrefetchSettingsNotifier extends StateNotifier<PrefetchSettings> {
  static const _keyEnabled = 'prefetch_enabled';
  static const _keyProfileId = 'prefetch_profile_id';

  PrefetchSettingsNotifier() : super(const PrefetchSettings()) {
    _loadSettings();
  }

  /// Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_keyEnabled) ?? false;
      final profileId = prefs.getString(_keyProfileId) ?? 'light';

      state = PrefetchSettings(
        enabled: enabled,
        selectedProfile: PrefetchProfile.fromId(profileId),
      );
    } catch (e) {
      // Fallback to defaults
    }
  }

  /// Toggle prefetch enabled/disabled
  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
  }

  /// Change selected profile
  Future<void> setProfile(PrefetchProfile profile) async {
    state = state.copyWith(selectedProfile: profile);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProfileId, profile.id);
  }
}

/// Provider for triggering prefetch actions
final prefetchActionsProvider = Provider<PrefetchActions>((ref) {
  return PrefetchActions(ref);
});

/// Prefetch action handlers
class PrefetchActions {
  final Ref _ref;

  PrefetchActions(this._ref);

  /// Start prefetch for current map view
  Future<void> prefetchCurrentView({
    required LatLng center,
    required String sourceId,
  }) async {
    final settings = _ref.read(prefetchSettingsProvider);
    if (!settings.enabled) {
      throw Exception('Prefetch is disabled in settings');
    }

    final orchestrator = _ref.read(prefetchOrchestratorProvider);
    await orchestrator.start(
      profile: settings.selectedProfile,
      center: center,
      sourceId: sourceId,
    );
  }

  /// Pause active prefetch
  void pause() {
    final orchestrator = _ref.read(prefetchOrchestratorProvider);
    orchestrator.pause();
  }

  /// Resume paused prefetch
  void resume() {
    final orchestrator = _ref.read(prefetchOrchestratorProvider);
    orchestrator.resume();
  }

  /// Cancel active prefetch
  Future<void> cancel() async {
    final orchestrator = _ref.read(prefetchOrchestratorProvider);
    await orchestrator.cancel();
  }
}
