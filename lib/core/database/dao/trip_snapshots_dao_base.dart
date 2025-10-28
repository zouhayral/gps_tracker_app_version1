import 'package:my_app_gps/data/models/trip_snapshot.dart';

abstract class TripSnapshotsDaoBase {
  Future<void> putSnapshot(TripSnapshot snapshot);
  Future<TripSnapshot?> getSnapshot(String monthKey);
  Future<List<TripSnapshot>> getAllSnapshots();
  Future<void> deleteOlderThan(String monthKey);
}
