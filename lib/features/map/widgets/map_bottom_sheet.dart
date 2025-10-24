import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Instant-response info sheet: reacts to drag updates immediately and snaps on release.
///
/// This bottom sheet provides:
/// - Smooth drag gestures with instant feedback
/// - Snap-to-position behavior (collapsed 5% or expanded 45%)
/// - Tap to toggle between states
/// - Velocity-based fling detection
/// - Haptic feedback for state changes
/// - Adaptive sizing with safe overflow handling
///
/// The sheet uses a custom gesture detector instead of DraggableScrollableSheet
/// for more responsive user interaction.
class MapBottomSheet extends StatefulWidget {
  const MapBottomSheet({
    required this.child,
    this.initialFraction = 0.45,
    this.minFraction = 0.05,
    this.maxFraction = 0.45,
    this.expandedColor = const Color(0xFF2196F3),
    this.collapsedColor = const Color(0xFFBDBDBD),
    this.borderColor = const Color(0xFFA6CD27),
    super.key,
  });

  /// The content to display inside the bottom sheet
  final Widget child;

  /// Initial height fraction (0.0 to 1.0) when sheet appears
  final double initialFraction;

  /// Minimum height fraction when collapsed (default: 0.05 = 5%)
  final double minFraction;

  /// Maximum height fraction when expanded (default: 0.45 = 45%)
  final double maxFraction;

  /// Color of the drag handle when expanded
  final Color expandedColor;

  /// Color of the drag handle when collapsed
  final Color collapsedColor;

  /// Color of the sheet border
  final Color borderColor;

  @override
  State<MapBottomSheet> createState() => MapBottomSheetState();
}

class MapBottomSheetState extends State<MapBottomSheet>
    with SingleTickerProviderStateMixin {
  late double _fraction;
  double _dragStart = 0;
  double _startFraction = 0;
  bool _isDragging = false;
  Duration _animDuration = const Duration(milliseconds: 200);
  Curve _animCurve = Curves.easeOutCubic;

  @override
  void initState() {
    super.initState();
    _fraction = widget.initialFraction.clamp(
      widget.minFraction,
      widget.maxFraction,
    );
  }

  /// Programmatically expand the sheet to maximum height with spring animation
  void expand() {
    _animDuration = const Duration(milliseconds: 280);
    _animCurve = Curves.easeOutBack;
    HapticFeedback.selectionClick();
    setState(() => _fraction = widget.maxFraction);
  }

  /// Programmatically collapse the sheet to minimum height with spring animation
  void collapse() {
    _animDuration = const Duration(milliseconds: 280);
    _animCurve = Curves.easeOutBack;
    HapticFeedback.selectionClick();
    setState(() => _fraction = widget.minFraction);
  }

  /// Check if the sheet is currently expanded
  bool get isExpanded => _fraction >= (widget.minFraction + widget.maxFraction) / 2;

  /// Check if the sheet is currently collapsed
  bool get isCollapsed => !isExpanded;

  void _onDragStart(DragStartDetails d) {
    _dragStart = d.globalPosition.dy;
    _startFraction = _fraction;
    _isDragging = true;
    // Instant reaction while dragging - no animation delay
    _animDuration = Duration.zero;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_isDragging) return;
    final delta = _dragStart - d.globalPosition.dy;
    final height = MediaQuery.of(context).size.height;
    final newFraction = (_startFraction + delta / height).clamp(
      widget.minFraction,
      widget.maxFraction,
    );
    setState(() => _fraction = newFraction);
  }

  void _onDragEnd(DragEndDetails d) {
    _isDragging = false;
    final velocity = d.primaryVelocity ?? 0;

    double target;
    // Velocity-based fling detection
    if (velocity < -300) {
      // Fast downward swipe -> expand
      target = widget.maxFraction;
    } else if (velocity > 300) {
      // Fast upward swipe -> collapse
      target = widget.minFraction;
    } else {
      // Slow drag -> snap to nearest state
      final midpoint = (widget.minFraction + widget.maxFraction) / 2;
      target = (_fraction < midpoint) ? widget.minFraction : widget.maxFraction;
    }

    HapticFeedback.selectionClick();
    // Smooth settle after drag ends
    _animDuration = const Duration(milliseconds: 220);
    _animCurve = Curves.easeOutCubic;
    setState(() => _fraction = target);
  }

  void _onTap() {
    final midpoint = (widget.minFraction + widget.maxFraction) / 2;
    final target = (_fraction < midpoint) ? widget.maxFraction : widget.minFraction;
    HapticFeedback.selectionClick();
    _animDuration = const Duration(milliseconds: 260);
    _animCurve = Curves.easeOutBack;
    setState(() => _fraction = target);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final midpoint = (widget.minFraction + widget.maxFraction) / 2;
    final isExpanded = _fraction > midpoint;

    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onTap: _onTap,
        behavior: HitTestBehavior.translucent,
        child: AnimatedContainer(
          duration: _animDuration,
          curve: _animCurve,
          height: screenHeight * _fraction,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: widget.borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.biggest.height;
              // Adapt the grab handle size/margins to avoid overflow on tiny heights
              final handleHeight = available.clamp(0, double.infinity) * 0.15;
              final safeHandleHeight = handleHeight.clamp(2.0, 8.0);
              final handleVMargin = (available * 0.10).clamp(4.0, 10.0);

              return Column(
                children: [
                  SizedBox(height: handleVMargin),
                  // Drag handle that changes color based on state
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56,
                    height: safeHandleHeight,
                    decoration: BoxDecoration(
                      color: isExpanded
                          ? widget.expandedColor
                          : widget.collapsedColor,
                      borderRadius: BorderRadius.circular(40),
                    ),
                  ),
                  SizedBox(height: handleVMargin),
                  // Ensure content never overflows: make it scrollable when space is tight
                  Expanded(
                    child: ClipRect(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        child: widget.child,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
