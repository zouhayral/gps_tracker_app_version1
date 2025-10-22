import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/objectbox_singleton.dart';
import 'package:my_app_gps/data/models/trip_snapshot.dart';
import 'package:my_app_gps/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as ob;

abstract class TripSnapshotsDaoBase {
  Future<void> putSnapshot(TripSnapshot snapshot);
  Future<TripSnapshot?> getSnapshot(String monthKey);
  Future<List<TripSnapshot>> getAllSnapshots();
  Future<void> deleteOlderThan(String monthKey);
}

class TripSnapshotsDaoObjectBox implements TripSnapshotsDaoBase {
  TripSnapshotsDaoObjectBox(this._store) : _box = _store.box<TripSnapshot>();
  // ignore: unused_field
  final ob.Store _store;
  final ob.Box<TripSnapshot> _box;

  @override
  Future<void> putSnapshot(TripSnapshot snapshot) async {
    // Ensure uniqueness by monthKey: replace if exists
    final q = _box.query(TripSnapshot_.monthKey.equals(snapshot.monthKey)).build();
    try {
      final existing = q.findFirst();
      if (existing != null) {
        snapshot.id = existing.id;
      }
      _box.put(snapshot);
    } finally {
      q.close();
    }
  }

  @override
  Future<TripSnapshot?> getSnapshot(String monthKey) async {
    final q = _box.query(TripSnapshot_.monthKey.equals(monthKey)).build();
    try {
      return q.findFirst();
    } finally {
      q.close();
    }
  }

  @override
  Future<List<TripSnapshot>> getAllSnapshots() async {
    final list = _box.getAll();
    list.sort((a, b) => a.monthKey.compareTo(b.monthKey));
    return list;
  }

  @override
  Future<void> deleteOlderThan(String monthKey) async {
    // yyyy-MM lexical order matches chronological; delete where monthKey < cutoff
    final all = _box.getAll();
    final ids = <int>[];
    for (final s in all) {
      if (s.monthKey.compareTo(monthKey) < 0) ids.add(s.id);
    }
    if (ids.isNotEmpty) {
      _box.removeMany(ids);
    }
  }
}

/// Provider exposing TripSnapshots DAO (ObjectBox-backed)
final tripSnapshotsDaoProvider = FutureProvider<TripSnapshotsDaoBase>((ref) async {
  final link = ref.keepAlive();
  Timer? timer;
  ref
    ..onCancel(() {
      timer?.cancel();
      timer = Timer(const Duration(minutes: 10), link.close);
    })
    ..onDispose(() => timer?.cancel());

  final store = await ObjectBoxSingleton.getStore();
  return TripSnapshotsDaoObjectBox(store);
});
