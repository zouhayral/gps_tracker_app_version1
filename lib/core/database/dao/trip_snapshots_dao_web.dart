import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/trip_snapshots_dao_base.dart';
import 'package:my_app_gps/data/models/trip_snapshot.dart';

class TripSnapshotsDaoWeb implements TripSnapshotsDaoBase {
  final Map<String, TripSnapshot> _map = <String, TripSnapshot>{};

  @override
  Future<void> putSnapshot(TripSnapshot snapshot) async {
    _map[snapshot.monthKey] = snapshot;
  }

  @override
  Future<TripSnapshot?> getSnapshot(String monthKey) async => _map[monthKey];

  @override
  Future<List<TripSnapshot>> getAllSnapshots() async {
    final list = _map.values.toList();
    list.sort((a, b) => a.monthKey.compareTo(b.monthKey));
    return list;
  }

  @override
  Future<void> deleteOlderThan(String monthKey) async {
    _map.removeWhere((k, v) => k.compareTo(monthKey) < 0);
  }
}

final tripSnapshotsDaoWebProvider = Provider<TripSnapshotsDaoBase>((ref) {
  return TripSnapshotsDaoWeb();
});

TripSnapshotsDaoBase createTripSnapshotsDao(Ref ref) {
  return ref.watch(tripSnapshotsDaoWebProvider);
}
