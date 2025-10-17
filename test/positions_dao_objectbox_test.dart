import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart' as hive;
import 'package:my_app_gps/core/database/dao/positions_dao.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/objectbox.g.dart';
// ignore_for_file: unused_import
import 'package:objectbox/objectbox.dart' as ob;
import 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';

import 'test_utils/test_config.dart';

void main() {
  setUpAll(() async {
    await setupTestEnvironment();
  });

  group('PositionsDaoObjectBox', () {
    Future<ob.Store?> tryOpenStore(Directory dir) async {
      try {
        final s = await openStore(directory: dir.path);
        return s;
      } catch (_) {
        return null;
      }
    }

    test('upsert and latest/loadAll', () async {
      if (!objectBoxAvailableForTests) {
        // ignore: avoid_print
        print('SKIP: ObjectBox native library not available on this env');
        return;
      }
      final tempDir = await Directory.systemTemp.createTemp('obx_test_');
      final store = await tryOpenStore(tempDir);
      if (store == null) {
        // Environment missing native ObjectBox library; skip.
        // ignore: avoid_print
        print('SKIP: ObjectBox native library not available on this env');
        await tempDir.delete(recursive: true);
        return;
      }
      final dao = PositionsDaoObjectBox(store);
      final p1 = Position(
        deviceId: 1,
        latitude: 10,
        longitude: 20,
        speed: 0,
        course: 0,
        deviceTime: DateTime.utc(2024),
        serverTime: DateTime.utc(2024, 1, 1, 0, 0, 1),
        attributes: const {'a': 1},
      );
      await dao.upsert(p1);
      final got1 = await dao.latestByDevice(1);
      expect(got1?.latitude, 10);

      // Update
      final p1b = Position(
        deviceId: 1,
        latitude: 11,
        longitude: 22,
        speed: 0,
        course: 0,
        deviceTime: DateTime.utc(2024, 1, 2),
        serverTime: DateTime.utc(2024, 1, 2, 0, 0, 1),
        attributes: const {'b': 2},
      );
      await dao.upsert(p1b);
      final got1b = await dao.latestByDevice(1);
      expect(got1b?.latitude, 11);

      final all = await dao.loadAll();
      expect(all.length, 1);
      expect(all[1]?.longitude, 22);
      store.close();
      await tempDir.delete(recursive: true);
    });

    test('migration from Hive', () async {
      if (!objectBoxAvailableForTests) {
        // ignore: avoid_print
        print('SKIP: ObjectBox native library not available on this env');
        return;
      }
      final tempDir = await Directory.systemTemp.createTemp('obx_test_');
      final store = await tryOpenStore(tempDir);
      if (store == null) {
        // ignore: avoid_print
        print('SKIP: ObjectBox native library not available on this env');
        await tempDir.delete(recursive: true);
        return;
      }
      final dao = PositionsDaoObjectBox(store);
      hive.Hive.init(tempDir.path);
      final box = await hive.Hive.openBox<String>('positions_last_known');
      final p = Position(
        deviceId: 9,
        latitude: 1,
        longitude: 2,
        speed: 0,
        course: 0,
        deviceTime: DateTime.utc(2023),
        serverTime: DateTime.utc(2023, 1, 1, 0, 0, 1),
        attributes: const {},
      );
      await box.put(
        p.deviceId,
        jsonEncode({
          'deviceId': p.deviceId,
          'latitude': p.latitude,
          'longitude': p.longitude,
          'speed': p.speed,
          'course': p.course,
          'deviceTime': p.deviceTime.toUtc().toIso8601String(),
          'serverTime': p.serverTime.toUtc().toIso8601String(),
          'attributes': p.attributes,
        }),
      );
      await box.close();

      await dao.migrateFromHiveIfPresent();
      final got = await dao.latestByDevice(9);
      expect(got?.latitude, 1);
      store.close();
      await tempDir.delete(recursive: true);
    });
  });
}
