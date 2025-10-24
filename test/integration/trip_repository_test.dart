import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/repositories/trip_repository.dart';
import 'package:my_app_gps/services/auth_service.dart';

/// Minimal HttpClientAdapter to mock Dio responses without network.
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }
}

class _FakeAuthService extends AuthService {
  _FakeAuthService(super.dio, super.jar, super.ref);

  @override
  Future<void> rehydrateSessionCookie() async {
    // No-op in tests (avoids secure storage access)
  }
}

void main() {
  group('TripRepository smoke tests', () {
    late ProviderContainer container;
    late Dio dio;
    late CookieJar jar;
    RequestOptions? lastOptions;

    setUp(() {
      lastOptions = null;
      jar = CookieJar();
      dio = Dio(BaseOptions(baseUrl: 'http://example.com'));
    });

    tearDown(() {
      container.dispose();
    });

    test('happy path: parses list and stringifies params', () async {
      final tripsJson = [
        {
          'deviceId': 1,
          'startTime': '2025-10-22T10:00:00Z',
          'endTime': '2025-10-22T11:00:00Z',
          'distance': 12000,
          'averageSpeed': 40,
          'maxSpeed': 60,
          'startLat': 0,
          'startLon': 0,
          'endLat': 1,
          'endLon': 1,
        }
      ];

      dio.httpClientAdapter = _MockAdapter((options) async {
        lastOptions = options;
        expect(options.path, '/api/reports/trips');
        // Ensure all params are strings
        options.queryParameters.forEach((k, v) {
          expect(v, isA<String>(), reason: 'Query param $k must be a String');
        });
        final body = jsonEncode(tripsJson);
        return ResponseBody.fromString(
          body,
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json; charset=utf-8'],
          },
        );
      });

      container = ProviderContainer(overrides: [
        dioProvider.overrideWithValue(dio),
        authCookieJarProvider.overrideWithValue(jar),
        authServiceProvider.overrideWith((ref) => _FakeAuthService(dio, jar, ref)),
      ],);

      final repo = container.read(tripRepositoryProvider);
      final from = DateTime.utc(2025, 10, 22, 10, 50, 9);
      final to = from.add(const Duration(days: 1));
      final trips = await repo.fetchTrips(deviceId: 1, from: from, to: to);

      expect(trips, isNotEmpty);
      expect(trips.first.deviceId, 1);
      // Verify stringified parameters were sent
      expect(lastOptions, isNotNull);
      expect(lastOptions!.queryParameters['deviceId'], '1');
      expect(lastOptions!.queryParameters['from'], isA<String>());
      expect(lastOptions!.queryParameters['to'], isA<String>());
    });

    test('empty list: returns empty without throwing', () async {
      dio.httpClientAdapter = _MockAdapter((options) async {
        lastOptions = options;
        return ResponseBody.fromString(
          '[]',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json; charset=utf-8'],
          },
        );
      });

      container = ProviderContainer(overrides: [
        dioProvider.overrideWithValue(dio),
        authCookieJarProvider.overrideWithValue(jar),
        authServiceProvider.overrideWith((ref) => _FakeAuthService(dio, jar, ref)),
      ],);

      final repo = container.read(tripRepositoryProvider);
      final now = DateTime.now().toUtc();
      final trips = await repo.fetchTrips(deviceId: 42, from: now, to: now);
      expect(trips, isEmpty);
    });

    test('malformed 200 response: returns empty defensively', () async {
      dio.httpClientAdapter = _MockAdapter((options) async {
        lastOptions = options;
        return ResponseBody.fromString(
          '{"not":"a list"}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json; charset=utf-8'],
          },
        );
      });

      container = ProviderContainer(overrides: [
        dioProvider.overrideWithValue(dio),
        authCookieJarProvider.overrideWithValue(jar),
        authServiceProvider.overrideWith((ref) => _FakeAuthService(dio, jar, ref)),
      ],);

      final repo = container.read(tripRepositoryProvider);
      final now = DateTime.now().toUtc();
      final trips = await repo.fetchTrips(deviceId: 7, from: now, to: now);
      expect(trips, isEmpty);
    });

    test('html 200 response: returns empty and does not throw', () async {
      dio.httpClientAdapter = _MockAdapter((options) async {
        lastOptions = options;
        return ResponseBody.fromString(
          '<html>not json</html>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        );
      });

      container = ProviderContainer(overrides: [
        dioProvider.overrideWithValue(dio),
        authCookieJarProvider.overrideWithValue(jar),
        authServiceProvider.overrideWith((ref) => _FakeAuthService(dio, jar, ref)),
      ],);

      final repo = container.read(tripRepositoryProvider);
      final now = DateTime.now().toUtc();
      final trips = await repo.fetchTrips(deviceId: 5, from: now, to: now);
      expect(trips, isEmpty);
    });
  });
}
