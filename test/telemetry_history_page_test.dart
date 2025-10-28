import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/features/telemetry/telemetry_history_page.dart';
import 'package:my_app_gps/features/telemetry/telemetry_history_provider.dart';

void main() {
  testWidgets('TelemetryHistoryPage shows empty state when no data',
      (tester) async {
    final container = ProviderContainer(overrides: [
      telemetryHistoryProvider
          .overrideWith((ref, deviceId) async => <TelemetrySample>[]),
    ],);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TelemetryHistoryPage(deviceId: 1)),
    ),);

    await tester.pumpAndSettle();

    expect(find.textContaining('No telemetry data'), findsOneWidget);
  });
}
