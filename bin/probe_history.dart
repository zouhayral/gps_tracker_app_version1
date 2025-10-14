import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/services/auth_service.dart';
import 'package:my_app_gps/services/positions_service.dart';

// Simple standalone runner to probe history batch size.
// Usage (PowerShell example):
//   $env:TRACCAR_BASE_URL='http://your-server:8082'; \
//   dart run bin/probe_history.dart <email> <password> <deviceId>
// Ensure the project dependencies are fetched (flutter pub get) beforehand.

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln(
      'Usage: dart run bin/probe_history.dart <email> <password> <deviceId>',
    );
    exit(64);
  }
  final email = args[0];
  final password = args[1];
  final deviceId = int.tryParse(args[2]);
  if (deviceId == null) {
    stderr.writeln('Invalid deviceId: ${args[2]}');
    exit(64);
  }

  // Minimal ProviderContainer since we are outside Flutter runtime.
  final container = ProviderContainer();
  final dio = container.read(dioProvider);
  final auth = container.read(authServiceProvider);

  stdout.writeln('Base URL: ${dio.options.baseUrl}');
  stdout.writeln('Logging in as $email ...');
  try {
    await auth.clearStoredSession();
    final user = await auth.login(email, password);
    stdout.writeln('Login OK. User id=${user['id']} name=${user['name']}');
  } on Exception catch (e) {
    stderr.writeln('Login failed: $e');
    exit(1);
  }

  final positionsService = container.read(positionsServiceProvider);
  stdout.writeln('Probing history window growth for deviceId=$deviceId ...');
  final steps = await positionsService.probeHistoryMax(deviceId: deviceId);
  stdout.writeln('--- Probe Results ---');
  for (final s in steps) {
    stdout.writeln(s.toString());
  }
  stdout.writeln(
    'Done. Interpret results and update docs/map_to_do.md Validation 0.2 section.',
  );
  container.dispose();
}
