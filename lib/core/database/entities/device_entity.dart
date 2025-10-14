import 'package:objectbox/objectbox.dart';

// TODO(OBX5): Verify entity constructors and query/watch semantics after upgrading
// to ObjectBox 5.x. Prefer named constructors over static factories where possible.

/// ObjectBox entity for Device persistence
@Entity()
class DeviceEntity {
  DeviceEntity({
    required this.deviceId,
    required this.name,
    required this.uniqueId,
    required this.status,
    this.id = 0,
    this.category,
    this.model,
    this.contact,
    this.phone,
    this.lastUpdate,
    this.disabled = false,
    this.attributesJson = '{}',
  });

  /// Local ObjectBox ID (auto-increment)
  @Id()
  int id;

  /// Backend device ID - indexed for fast lookups
  @Unique()
  @Index()
  int deviceId;

  /// Device name
  String name;

  /// Unique identifier (IMEI, serial, etc.)
  @Index()
  String uniqueId;

  /// Device status: online, offline, unknown
  @Index()
  String status;

  /// Optional fields for extended device info
  String? category;
  String? model;
  String? contact;
  String? phone;

  /// Last update timestamp in milliseconds since epoch
  @Index()
  int? lastUpdate;

  /// Whether device is disabled
  bool disabled;

  /// JSON string for additional attributes
  String attributesJson;

  /// Factory constructor from domain entity
  factory DeviceEntity.fromDomain(
    int deviceId,
    String name,
    String uniqueId,
    String status, {
    String? category,
    String? model,
    String? contact,
    String? phone,
    DateTime? lastUpdate,
    bool disabled = false,
    Map<String, dynamic>? attributes,
  }) {
    return DeviceEntity(
      deviceId: deviceId,
      name: name,
      uniqueId: uniqueId,
      status: status,
      category: category,
      model: model,
      contact: contact,
      phone: phone,
      lastUpdate: lastUpdate?.toUtc().millisecondsSinceEpoch,
      disabled: disabled,
      attributesJson:
          attributes != null ? _encodeAttributes(attributes) : '{}',
    );
  }

  /// Convert to domain entity (simplified)
  Map<String, dynamic> toDomain() {
    return {
      'id': deviceId,
      'name': name,
      'uniqueId': uniqueId,
      'status': status,
      'category': category,
      'model': model,
      'contact': contact,
      'phone': phone,
      'lastUpdate': lastUpdate != null
          ? DateTime.fromMillisecondsSinceEpoch(lastUpdate!, isUtc: true)
              .toLocal()
          : null,
      'disabled': disabled,
      'attributes': _decodeAttributes(attributesJson),
    };
  }

  static String _encodeAttributes(Map<String, dynamic> attributes) {
    try {
      return attributes.toString();
    } catch (_) {
      return '{}';
    }
  }

  static Map<String, dynamic> _decodeAttributes(String json) {
    try {
      // Simple parsing - enhance if needed
      return {};
    } catch (_) {
      return {};
    }
  }
}
