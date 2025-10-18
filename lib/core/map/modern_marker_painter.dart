import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Painter that draws markers matching the uploaded design set:
/// - State 1 (online + ignition ON + stopped): green pin with car icon and green power badge
/// - State 2 (online + ignition ON + moving): green circle with motion trail and orange power badge
/// - State 3 (online + ignition OFF + stopped): green circle with red badge
/// - State 4 (offline): grey circle with red badge
/// - State 5 (offline + ignition OFF): amber/yellow circle with red badge
class ModernMarkerPainter extends CustomPainter {
  ModernMarkerPainter({
    required this.name,
    required this.online,
    required this.engineOn,
    required this.moving,
    required this.compact,
    this.speed,
  });

  final String name;
  final bool online;
  final bool engineOn;
  final bool moving;
  final bool compact;
  final double? speed;

  // App color scheme
  static const _appGreen = Color(0xFFA6CD27);
  static const _dangerRed = Color(0xFFFF383C);
  static const _offlineGrey = Color(0xFF9E9E9E);
  static const _warningAmber = Color(0xFFFFC107);

  @override
  void paint(Canvas canvas, Size size) {
    // Shape is decided by state rather than compact flag.
    final isPin = online && engineOn && !moving;
    if (isPin) {
      _drawPinMarker(canvas, size);
    } else {
      _drawCircularMarker(canvas, size);
    }

    // Top-left status badge
    _drawStatusBadge(canvas, size);

    // Motion/detail indicator
    if (online && engineOn && moving) {
      _drawMotionTrail(canvas, size);
    } else {
      _drawBottomDot(canvas, size);
    }
  }

  void _drawPinMarker(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Pin body (circle + tail)
    final path = Path();
    path.addOval(Rect.fromCircle(center: center, radius: radius));
    // Tail
    const tailHeight = 10.0;
    path.moveTo(center.dx - 8, center.dy + radius - 2);
    path.lineTo(center.dx, center.dy + radius + tailHeight);
    path.lineTo(center.dx + 8, center.dy + radius - 2);
    path.close();

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path.shift(const Offset(0, 2)), shadowPaint);

    // Main fill (green)
    final fillPaint = Paint()..color = _appGreen;
    canvas.drawPath(path, fillPaint);

    // White inner ring
    final inner1 = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius * 0.75, inner1);

    // Green inner circle
    final inner2 = Paint()..color = _appGreen;
    canvas.drawCircle(center, radius * 0.58, inner2);

  // Car icon (Material, front view)
  _drawCarIcon(canvas, center, radius * 0.95);

    // Border for inner white ring
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius * 0.75, border);
  }

  void _drawCircularMarker(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Decide base color by state
    Color base;
    if (!online && !engineOn) {
      base = _warningAmber; // State 5
    } else if (!online) {
      base = _offlineGrey; // State 4
    } else {
      base = _appGreen; // States 2 and 3
    }

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center.translate(0, 1.5), radius, shadowPaint);

    // Main circle
    final main = Paint()..color = base;
    canvas.drawCircle(center, radius, main);

    // White inner ring
    final inner1 = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius * 0.72, inner1);

    // Inner colored disk
    final inner2 = Paint()..color = base;
    canvas.drawCircle(center, radius * 0.56, inner2);

    // Center glyph: rotating arrow if moving, else car front
    if (online && engineOn && moving) {
      _drawRotateGlyph(canvas, center, radius * 0.44);
    } else {
      _drawCarIcon(canvas, center, radius * 0.8);
    }

    // Border around white ring
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius * 0.72, border);
  }

  void _drawStatusBadge(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.18, size.height * 0.18);
    const r = 7.0;

    Color badge;
    // Icon: always a power symbol; color indicates state (ON/OFF/NEUTRAL)
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    // Three-color scheme for ignition state:
    // - NEUTRAL (disconnected): grey
    // - ON: green
    // - OFF: red
    if (!online) {
      badge = _offlineGrey; // Neutral when device disconnected
    } else if (engineOn) {
      badge = _appGreen; // ON
    } else {
      badge = _dangerRed; // OFF
    }

    // Badge background
    final bg = Paint()..color = badge;
    canvas.drawCircle(center, r, bg);

    // White border
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, r, border);

    // Icon: power symbol for all states
    const s = r * 0.55;
    // stem
    canvas.drawLine(center.translate(0, -s), center, iconPaint);
    // arc
    final rect = Rect.fromCircle(center: center, radius: s * 0.85);
    canvas.drawArc(rect, -3.4, 5.8, false, iconPaint);
  }

  void _drawMotionTrail(Canvas canvas, Size size) {
    // Three trailing dots bottom-right with decreasing size/opacity
    final start = Offset(size.width * 0.68, size.height * 0.7);
    const spacing = 6.0;
    const base = 2.5;
    for (var i = 0; i < 3; i++) {
      final paint = Paint()
        ..color = _appGreen.withOpacity(1.0 - i * 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(start.translate(i * spacing * 0.7, i * spacing * 0.7), base * (1.0 - i * 0.15), paint);
    }
  }

  void _drawBottomDot(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.9);
    final c = !online && !engineOn
        ? _warningAmber
        : (!online ? _offlineGrey : _appGreen);
    final p = Paint()..color = c;
    canvas.drawCircle(center, 2.5, p);
  }

  void _drawCarIcon(Canvas canvas, Offset center, double box) {
    // Draw a Material car icon centered (no flip). Box is the outer square size.
    const icon = Icons.directions_car_rounded;
    final size = box; // font size roughly equals visual height
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: Colors.white,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = Offset(center.dx - tp.width / 2, center.dy - tp.height / 2);
    tp.paint(canvas, offset);
  }

  void _drawRotateGlyph(Canvas canvas, Offset center, double r) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: r * 0.8);
    canvas.drawArc(rect, -1.2, 5, false, p);
    // arrow head
    final ah = Path()
      ..moveTo(center.dx + r * 0.8, center.dy)
      ..lineTo(center.dx + r * 0.8 - 3, center.dy - 3)
      ..lineTo(center.dx + r * 0.8 - 3, center.dy + 3)
      ..close();
    final fill = Paint()..color = Colors.white;
    canvas.drawPath(ah, fill);
  }

  @override
  bool shouldRepaint(ModernMarkerPainter oldDelegate) {
    return oldDelegate.name != name ||
        oldDelegate.online != online ||
        oldDelegate.engineOn != engineOn ||
        oldDelegate.moving != moving ||
        oldDelegate.speed != speed ||
        oldDelegate.compact != compact;
  }
}

/// Widget wrapper for modern marker (for rendering to image)
class ModernMarkerWidget extends StatelessWidget {
  const ModernMarkerWidget({
    required this.name,
    required this.online,
    required this.engineOn,
    required this.moving,
    this.compact = false,
    this.speed,
    super.key,
  });

  final String name;
  final bool online;
  final bool engineOn;
  final bool moving;
  final bool compact;
  final double? speed;

  @override
  Widget build(BuildContext context) {
    final size = compact ? const Size(48, 48) : const Size(56, 56);

    return SizedBox(
      width: size.width,
      height: size.height,
      child: CustomPaint(
        painter: ModernMarkerPainter(
          name: name,
          online: online,
          engineOn: engineOn,
          moving: moving,
          compact: compact,
          speed: speed,
        ),
      ),
    );
  }
}

/// Marker size configuration
enum MarkerSize {
  /// Full details: 56x56 (larger, selected marker)
  full(56, 56),

  /// Compact: 48x48 (normal marker)
  compact(48, 48);

  const MarkerSize(this.width, this.height);
  final double width;
  final double height;
}
