// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'test_freezed.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TestFreezed _$TestFreezedFromJson(Map<String, dynamic> json) => _TestFreezed(
  isActive: json['isActive'] as bool? ?? false,
  count: (json['count'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$TestFreezedToJson(_TestFreezed instance) =>
    <String, dynamic>{'isActive': instance.isActive, 'count': instance.count};
