import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/network/connectivity_manager.dart';

class FakeConnectivitySource implements ConnectivitySource {
  FakeConnectivitySource(this._initial);

  final List<ConnectivityResult> _initial;
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _initial;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;

  // helper
  void emit(List<ConnectivityResult> results) => _controller.add(results);

  Future<void> close() => _controller.close();
}

void main() {
  group('ConnectivityManager', () {
    test('initial state reflects checkConnectivity()', () async {
      final fake = FakeConnectivitySource(const [ConnectivityResult.none]);
      final mgr = ConnectivityManager(source: fake);

      await mgr.initialize();

      expect(mgr.isOfflineNow, isTrue);

      await fake.close();
      mgr.dispose();
    });

    test('updates isOffline on stream changes', () async {
      final fake = FakeConnectivitySource(const [ConnectivityResult.none]);
      final mgr = ConnectivityManager(source: fake);

      await mgr.initialize();
      expect(mgr.isOffline.value, isTrue);

      // Go online via Wi-Fi
      fake.emit(const [ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(mgr.isOffline.value, isFalse);

      // Go offline again
      fake.emit(const [ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(mgr.isOfflineNow, isTrue);

      await fake.close();
      mgr.dispose();
    });

    test('treats empty list as offline (defensive)', () async {
      final fake = FakeConnectivitySource(const []);
      final mgr = ConnectivityManager(source: fake);

      await mgr.initialize();
      expect(mgr.isOfflineNow, isTrue);

      await fake.close();
      mgr.dispose();
    });
  });
}
