import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/debug/rebuild_counter.dart';

extension RebuildLogger on WidgetRef {
  void logRebuild(String name) {
    debugPrint(
      '[REBUILD] $name rebuilt at ${DateTime.now().toIso8601String()}',
    );
    RebuildCounter.increment();
  }

  void scheduleLogRebuild(String name) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) logRebuild(name);
    });
  }
}
