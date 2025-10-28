import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Extension providing safe navigation methods that prevent crashes
/// from popping the last page or navigating after widget disposal.
///
/// Fixes crash: "You have popped the last page off of the stack"
extension SafeNavigation on BuildContext {
  /// Safely pop the current route. If at the root of the navigation stack,
  /// redirects to the map page instead of attempting to pop.
  ///
  /// Also checks if the widget is still mounted before navigation.
  Future<void> safePop<T>([T? result]) async {
    if (!mounted) {
      debugPrint('[SafeNav] ⚠️ Context not mounted, skipping pop');
      return;
    }

    final navigator = Navigator.of(this);
    if (navigator.canPop()) {
      navigator.pop(result);
      debugPrint('[SafeNav] ✅ Popped route successfully');
    } else {
      // At root of stack - redirect to map instead of crashing
      debugPrint('[SafeNav] ⚠️ At root, redirecting to map');
      if (mounted) go('/map');
    }
  }

  /// Safely navigate to a location using GoRouter.go()
  /// Checks if context is still mounted before navigation.
  Future<void> safeGo(String location, {Object? extra}) async {
    if (!mounted) {
      debugPrint('[SafeNav] ⚠️ Context not mounted, skipping go($location)');
      return;
    }
    go(location, extra: extra);
    debugPrint('[SafeNav] ✅ Navigated to $location');
  }

  /// Safely push a new route using GoRouter.push()
  /// Checks if context is still mounted before navigation.
  Future<T?> safePush<T>(String location, {Object? extra}) async {
    if (!mounted) {
      debugPrint('[SafeNav] ⚠️ Context not mounted, skipping push($location)');
      return null;
    }
    final result = await push<T>(location, extra: extra);
    debugPrint('[SafeNav] ✅ Pushed $location');
    return result;
  }

  /// Safely replace the current route
  /// Checks if context is still mounted before navigation.
  Future<void> safeReplace(String location, {Object? extra}) async {
    if (!mounted) {
      debugPrint('[SafeNav] ⚠️ Context not mounted, skipping replace($location)');
      return;
    }
    replace(location, extra: extra);
    debugPrint('[SafeNav] ✅ Replaced with $location');
  }

  /// Safely pop and push a new route
  /// Checks if context is still mounted and can pop before navigation.
  Future<T?> safePopAndPush<T>(String location, {Object? extra}) async {
    if (!mounted) {
      debugPrint('[SafeNav] ⚠️ Context not mounted, skipping popAndPush($location)');
      return null;
    }

    final navigator = Navigator.of(this);
    if (!navigator.canPop()) {
      // Can't pop, just go to location instead
      debugPrint('[SafeNav] ⚠️ At root, using go() instead of popAndPush()');
      if (mounted) go(location, extra: extra);
      return null;
    }

    // Safe to pop and push
    navigator.pop();
    if (mounted) {
      return push<T>(location, extra: extra);
    }
    return null;
  }

  /// Check if the navigator can pop without causing a crash
  bool get canSafelyPop {
    if (!mounted) return false;
    return Navigator.of(this).canPop();
  }
}
