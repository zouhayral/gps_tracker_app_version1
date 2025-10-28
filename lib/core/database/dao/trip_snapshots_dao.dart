import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/trip_snapshots_dao_base.dart';
// ignore: uri_does_not_exist
import 'package:my_app_gps/core/database/dao/trip_snapshots_dao_mobile.dart'
    if (dart.library.html) 'package:my_app_gps/core/database/dao/trip_snapshots_dao_web.dart'
    as platform;

export 'package:my_app_gps/core/database/dao/trip_snapshots_dao_base.dart';

/// Unified provider that returns a TripSnapshotsDaoBase.
/// Exposed as a FutureProvider to maintain compatibility with code using
/// `tripSnapshotsDaoProvider.future`.
final tripSnapshotsDaoProvider = FutureProvider<TripSnapshotsDaoBase>((ref) async {
  return platform.createTripSnapshotsDao(ref);
});
