import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';

final deviceServiceProvider = Provider<DeviceService>((ref) {
	final dio = ref.watch(dioProvider); // reuse dio with cookie manager
	return DeviceService(dio);
});

class DeviceService {
	DeviceService(this._dio);
	final Dio _dio;

	Future<List<Map<String, dynamic>>> fetchDevices() async {
		final resp = await _dio.get('/api/devices');
		if (resp.data is List) {
			return (resp.data as List)
				.whereType<Map>()
				.map((e) {
					final m = Map<String, dynamic>.from(e);
					final lu = m['lastUpdate'];
					if (lu is String) {
						final dt = DateTime.tryParse(lu);
						if (dt != null) m['lastUpdateDt'] = dt.toUtc();
					}
					return m;
				})
				.toList();
		}
		return [];
	}
}
