class Position {
  final int deviceId;
  final double latitude;
  final double longitude;
  final double speed;
  final double course;
  final DateTime deviceTime;
  final DateTime serverTime;
  final Map<String, dynamic> attributes;
  final int? id;
  final double? altitude;
  final double? accuracy;
  final bool? valid;
  final String? address;

  const Position({
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.course,
    required this.deviceTime,
    required this.serverTime,
    required this.attributes,
    this.id,
    this.altitude,
    this.accuracy,
    this.valid,
    this.address,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    double _d(String k) => (json[k] as num?)?.toDouble() ?? 0.0;
    DateTime _dt(String k) => DateTime.tryParse(json[k]?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    return Position(
      id: json['id'] as int?,
      deviceId: json['deviceId'] as int? ?? json['device_id'] as int? ?? 0,
      latitude: _d('latitude'),
      longitude: _d('longitude'),
      speed: _d('speed'),
      course: _d('course'),
      altitude: (json['altitude'] as num?)?.toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      valid: json['valid'] as bool?,
      address: json['address'] as String?,
      deviceTime: _dt('deviceTime'),
      serverTime: _dt('serverTime'),
      attributes: (json['attributes'] is Map<String, dynamic>) ? (json['attributes'] as Map<String, dynamic>) : <String, dynamic>{},
    );
  }
}
// (Freezed-based version removed for simplicity while bootstrapping.)
