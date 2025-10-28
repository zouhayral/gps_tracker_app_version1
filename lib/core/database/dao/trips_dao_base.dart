import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';

/// Abstraction for trip persistence using domain models (web-safe)
abstract class TripsDaoBase {
  Future<void> upsert(Trip trip);
  Future<void> upsertMany(List<Trip> trips);
  Future<Trip?> getById(String tripId);
  Future<List<Trip>> getByDevice(int deviceId);
  Future<List<Trip>> getByDeviceInRange(
    int deviceId,
    DateTime startTime,
    DateTime endTime,
  );
  Future<List<Trip>> getAll();
  Future<void> delete(String tripId);
  Future<void> deleteAll();
  Future<List<Trip>> getOlderThan(DateTime cutoff);
  Future<int> deleteOlderThan(DateTime cutoff);
  Future<List<Trip>> getTripsForPeriod(DateTime from, DateTime to);
  Future<Map<String, TripAggregate>> getAggregatesByDay(
    DateTime from,
    DateTime to,
  );
}
