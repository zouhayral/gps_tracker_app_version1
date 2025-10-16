import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/sync/adaptive_sync_manager.dart';

/// Provider for the app lifecycle observer
final appLifecycleObserverProvider = Provider<AppLifecycleObserver>((ref) {
  final adaptiveSyncManager = ref.watch(adaptiveSyncManagerProvider);

  final observer = AppLifecycleObserver(adaptiveSyncManager: adaptiveSyncManager);

  // Register observer with Flutter's binding
  WidgetsBinding.instance.addObserver(observer);

  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(observer);
  });

  return observer;
});

/// Observes app lifecycle changes and notifies AdaptiveSyncManager
/// 
/// This widget observer listens to Flutter's AppLifecycleState changes and
/// forwards them to the AdaptiveSyncManager for adaptive sync interval adjustment.
/// 
/// **States:**
/// - `resumed`: App is visible and responding to user input
/// - `inactive`: App is in transition (e.g., incoming call overlay)
/// - `paused`: App is not visible, running in background
/// - `detached`: App is detached from the Flutter engine
/// - `hidden`: App is hidden (Flutter 3.13+)
/// 
/// **Integration:**
/// The observer is automatically initialized when `appLifecycleObserverProvider` is accessed.
/// Typically, this happens in the app's main widget or initialization flow.
/// 
/// **Example:**
/// ```dart
/// class MyApp extends ConsumerWidget {
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     // Initialize lifecycle observer
///     ref.watch(appLifecycleObserverProvider);
///     
///     return MaterialApp(
///       // ...
///     );
///   }
/// }
/// ```
class AppLifecycleObserver extends WidgetsBindingObserver {
  AppLifecycleObserver({required this.adaptiveSyncManager});

  final AdaptiveSyncManager adaptiveSyncManager;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Notify adaptive sync manager about lifecycle change
    adaptiveSyncManager.notifyLifecycleChange(state);
  }
}
