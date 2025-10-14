// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/app/app_root.dart';

void main() {
  testWidgets('App boots and shows either Login or Map', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AppRoot())),
    );
    // Allow initial async auth check.
    await tester.pump(const Duration(milliseconds: 100));

    // Expect either login welcome text or map navigation label.
    final loginFinder = find.text('welcome back');
    final mapFinder = find.text('Map');
    final foundLogin = loginFinder.evaluate().isNotEmpty;
    final foundMap = mapFinder.evaluate().isNotEmpty;
    expect(
      foundLogin || foundMap,
      isTrue,
      reason: 'Should show login welcome or map navigation bar at startup',
    );
  });
}
