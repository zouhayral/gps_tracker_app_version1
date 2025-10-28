// Conditional shim: export base API and forward provider to platform impl.
// Prefer mobile implementation on IO platforms, otherwise web.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao_base.dart';
// ignore: uri_does_not_exist
import 'package:my_app_gps/core/database/dao/telemetry_dao_mobile.dart'
    if (dart.library.html) 'package:my_app_gps/core/database/dao/telemetry_dao_web.dart'
    as platform;

export 'package:my_app_gps/core/database/dao/telemetry_dao_base.dart';

/// Unified provider that returns a TelemetryDaoBase synchronously.
/// On mobile, uses a no-op until ObjectBox store is ready.
final telemetryDaoProvider = Provider<TelemetryDaoBase>(platform.createTelemetryDao);
