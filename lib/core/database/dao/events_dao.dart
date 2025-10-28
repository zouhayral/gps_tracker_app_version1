// Conditional implementation shim for Events DAO
import 'package:my_app_gps/core/database/dao/events_dao_mobile.dart'
    if (dart.library.html) 'package:my_app_gps/core/database/dao/events_dao_web.dart'
    as impl;

export 'package:my_app_gps/core/database/dao/events_dao_base.dart';

// Forward the platform-specific provider
final eventsDaoProvider = impl.eventsDaoProvider;
