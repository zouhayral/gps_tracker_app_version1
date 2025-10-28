import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/trips_dao_base.dart';
// ignore: uri_does_not_exist
import 'package:my_app_gps/core/database/dao/trips_dao_mobile.dart'
    if (dart.library.html) 'package:my_app_gps/core/database/dao/trips_dao_web.dart'
    as platform;

export 'package:my_app_gps/core/database/dao/trips_dao_base.dart';

/// Unified provider that returns a TripsDaoBase.
/// Exposed as a FutureProvider to maintain compatibility with existing code
/// that reads `tripsDaoProvider.future`.
final tripsDaoProvider = FutureProvider<TripsDaoBase>((ref) async {
  return platform.createTripsDao(ref);
});
