import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/services/device_service.dart';

// Keep devices in memory across tab switches (no autoDispose)
final devicesNotifierProvider = StateNotifierProvider<DevicesNotifier,
    AsyncValue<List<Map<String, dynamic>>>>((ref) {
  final service = ref.watch(deviceServiceProvider);
  return DevicesNotifier(
    service,
  ); // Remove auto-load, will be triggered by auth state changes
});

class DevicesNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  DevicesNotifier(this._service) : super(const AsyncValue.loading());
  final DeviceService _service;

  Future<void> load() async {
    try {
      state = const AsyncValue.loading();
      // 🎯 PHASE 2: Use throttled cache
      final devices = await _service.fetchDevices();
      state = AsyncValue.data(devices);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Clear devices data (useful when logging out or switching users)
  void clear() {
    state = const AsyncValue.loading();
    // 🎯 PHASE 2: Clear cache on logout
    _service.clearCache();
  }

  /// Force refresh devices (bypasses cache)
  Future<void> refresh() async {
    try {
      state = const AsyncValue.loading();
      // 🎯 PHASE 2: Force refresh bypasses cache
      final devices = await _service.fetchDevices(forceRefresh: true);
      state = AsyncValue.data(devices);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
  
  /// 🎯 PHASE 2: Get cache statistics
  Map<String, dynamic> getCacheStats() => _service.getCacheStats();
}
