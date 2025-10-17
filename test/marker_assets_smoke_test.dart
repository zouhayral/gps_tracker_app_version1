import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/features/map/view/marker_assets.dart';

void main() {
  testWidgets('MarkerAssets.preload loads SVGs without error',
      (WidgetTester tester) async {
    // Render an empty app to obtain a BuildContext
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    // Run async preload in the test environment
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(SizedBox));
      await precacheCommonMarkers(ctx);
    });

    // If no exceptions thrown during preload, test is considered successful
    expect(true, isTrue);
  });
}
