// Conditional implementation shim for Devices DAO
import 'package:my_app_gps/core/database/dao/devices_dao_mobile.dart'
    if (dart.library.html) 'package:my_app_gps/core/database/dao/devices_dao_web.dart'
    as impl;

export 'package:my_app_gps/core/database/dao/devices_dao_base.dart';

// Forward the platform-specific provider
final devicesDaoProvider = impl.devicesDaoProvider;
