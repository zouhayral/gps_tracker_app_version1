import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class FpsMonitor extends StatefulWidget {
  const FpsMonitor({super.key});
  @override
  State<FpsMonitor> createState() => _FpsMonitorState();
}

class _FpsMonitorState extends State<FpsMonitor> {
  double _fps = 0;
  TimingsCallback? _callback;

  @override
  void initState() {
    super.initState();
    _callback = (List<FrameTiming> timings) {
      if (timings.isEmpty) return;
      final frameTime = timings.last.totalSpan.inMicroseconds / 1e6;
  final fps = frameTime > 0 ? (1.0 / frameTime) : 0.0;
  if (mounted) setState(() => _fps = fps);
    };
    SchedulerBinding.instance.addTimingsCallback(_callback!);
  }

  @override
  void dispose() {
    if (_callback != null) SchedulerBinding.instance.removeTimingsCallback(_callback!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned(
    bottom: 12, right: 12,
    child: DecoratedBox(
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text('FPS: ${_fps.toStringAsFixed(1)}',
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    ),
  );
}
