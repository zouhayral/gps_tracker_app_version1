import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/services/auth_service.dart';

final deviceServiceProvider = Provider<DeviceService>((ref) {
  final dio = ref.watch(dioProvider); // reuse dio with cookie manager
  return DeviceService(dio);
});

class DeviceService {
  DeviceService(this._dio);
  final Dio _dio;

  Future<List<Map<String, dynamic>>> fetchDevices() async {
    final resp = await _dio.get<List<dynamic>>('/api/devices');
    final data = resp.data;
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final lu = m['lastUpdate'];
        if (lu is String) {
          final dt = DateTime.tryParse(lu);
          if (dt != null) m['lastUpdateDt'] = dt.toUtc();
        }
        return m;
      }).toList();
    }
    return [];
  }
}
