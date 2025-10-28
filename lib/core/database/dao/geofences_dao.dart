// Conditional implementation shim
import 'package:my_app_gps/core/database/dao/geofences_dao_mobile.dart'
    if (dart.library.html) 'package:my_app_gps/core/database/dao/geofences_dao_web.dart'
    as impl;

export 'package:my_app_gps/core/database/dao/geofences_dao_base.dart';

// Forward the platform-specific provider
final geofencesDaoProvider = impl.geofencesDaoProvider;
