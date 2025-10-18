import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:my_app_gps/features/map/clustering/cluster_models.dart';

/// Lightweight spiderfy overlay for small clusters (<= 5 markers).
///
/// Shows radial expansion of markers around the cluster center.
class SpiderfyOverlay extends StatefulWidget {
  const SpiderfyOverlay({
    required this.center,
    required this.members,
    required this.onDismiss,
    super.key,
  });

  final LatLng center;
  final List<ClusterableMarker> members;
  final VoidCallback onDismiss;

  static OverlayEntry show(
    BuildContext context, {
    required LatLng center,
    required List<ClusterableMarker> members,
  }) {
    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (ctx) => SpiderfyOverlay(
        center: center,
        members: members,
        onDismiss: () => overlayEntry.remove(),
      ),
    );

    final overlay = Overlay.of(context, rootOverlay: true);
    overlay.insert(overlayEntry);
    return overlayEntry;
  }

  @override
  State<SpiderfyOverlay> createState() => _SpiderfyOverlayState();
}

class _SpiderfyOverlayState extends State<SpiderfyOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.members.length;
    const angleStep = (2 * math.pi) / 5; // max 5 members
    const radius = 56.0; // logical px spread

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onDismiss,
      onPanStart: (_) => widget.onDismiss(),
      child: Stack(
        children: [
          // TODO(ux): Convert LatLng to screen position using map controller if available.
          // Here we use Center as a placeholder visual; integration should position relative to map.
          Center(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, child) {
                final children = <Widget>[];
                for (var i = 0; i < count; i++) {
                  final angle = i * angleStep;
                  final dx = math.cos(angle) * radius * _anim.value;
                  final dy = math.sin(angle) * radius * _anim.value;

                  children.add(
                    Transform.translate(
                      offset: Offset(dx, dy),
                      child: _SpiderDot(label: widget.members[i].id),
                    ),
                  );
                }
                return Stack(children: children);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SpiderDot extends StatelessWidget {
  const _SpiderDot({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.blueAccent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Tooltip(
        message: label,
        child: const Icon(Icons.circle, size: 8, color: Colors.white),
      ),
    );
  }
}
