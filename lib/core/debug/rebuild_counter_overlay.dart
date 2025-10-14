import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:my_app_gps/core/debug/rebuild_counter.dart';

class RebuildCounterOverlay extends StatelessWidget {
  const RebuildCounterOverlay({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    assert(
      debugCheckHasDirectionality(context),
      'Directionality missing: RebuildCounterOverlay requires a Directionality ancestor',
    );
    if (!kDebugMode) return child;
    return Stack(
      children: [
        child,
        Positioned(
          right: 8,
          top: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ValueListenableBuilder<int>(
                valueListenable: RebuildCounter.count,
                builder: (context, v, _) => Text(
                  'Rebuilds: $v',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
