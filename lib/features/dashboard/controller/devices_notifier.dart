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
      final devices = await _service.fetchDevices();
      state = AsyncValue.data(devices);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Clear devices data (useful when logging out or switching users)
  void clear() {
    state = const AsyncValue.loading();
  }

  /// Force refresh devices for new user
  Future<void> refresh() async {
    await load();
  }
}
