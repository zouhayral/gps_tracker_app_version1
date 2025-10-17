import 'dart:convert';

import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:objectbox/objectbox.dart';

// TODO(OBX5): When migrating to ObjectBox 5, verify query/watch APIs and re-run
// codegen. Ensure named constructors remain compatible with the new generator.

@Entity()
class PositionEntity {
  PositionEntity({
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.course,
    required this.deviceTimeMs,
    required this.serverTimeMs,
    required this.attributesJson,
    this.id = 0,
  });

  @Id()
  int id;

  @Unique()
  @Index()
  int deviceId;

  double latitude;
  double longitude;
  double speed;
  double course;

  // Store DateTime as milliseconds since epoch UTC for compactness
  @Index()
  int deviceTimeMs;
  @Index()
  int serverTimeMs;

  // JSON string for attributes map
  String attributesJson;

  PositionEntity.fromPosition(Position p)
      : id = 0,
        deviceId = p.deviceId,
        latitude = p.latitude,
        longitude = p.longitude,
        speed = p.speed,
        course = p.course,
        deviceTimeMs = p.deviceTime.toUtc().millisecondsSinceEpoch,
        serverTimeMs = p.serverTime.toUtc().millisecondsSinceEpoch,
        attributesJson = jsonEncode(p.attributes);

  Position toPosition() => Position(
        deviceId: deviceId,
        latitude: latitude,
        longitude: longitude,
        speed: speed,
        course: course,
        deviceTime:
            DateTime.fromMillisecondsSinceEpoch(deviceTimeMs, isUtc: true)
                .toLocal(),
        serverTime:
            DateTime.fromMillisecondsSinceEpoch(serverTimeMs, isUtc: true)
                .toLocal(),
        attributes: jsonDecode(attributesJson) as Map<String, dynamic>,
      );
}
