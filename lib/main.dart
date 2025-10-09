import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart/app_root.dart';

void main() {
  // Capture framework errors and avoid giant solid red rectangles.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // ignore: avoid_print
    print('FlutterError: ${details.exceptionAsString()}');
  };
  ErrorWidget.builder = (FlutterErrorDetails d) {
    // Compact inline error widget instead of full red screen.
    return Center(
      child: Card(
        color: Colors.red.shade700,
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            'UI error: ${d.exception}\nTap back or continue.',
            style: const TextStyle(color: Colors.white, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const AppRoot();
}

