import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

void main() {
  test('Position.fromJson parses minimal fields', () {
    final json = {
      'id': 123,
      'deviceId': 42,
      'latitude': 12.34,
      'longitude': 56.78,
      'speed': 10,
      'course': 90,
      'deviceTime': '2024-01-01T00:00:00Z',
      'serverTime': '2024-01-01T00:00:01Z',
      'attributes': {'ignition': true},
    };
    final p = Position.fromJson(json);
    expect(p.deviceId, 42);
    expect(p.latitude, 12.34);
    expect(p.longitude, 56.78);
    expect(p.speed, 10);
    expect(p.course, 90);
    expect(p.attributes['ignition'], true);
    // Basic field checks done above; JSON serialization is covered by other layers.
  });
}
