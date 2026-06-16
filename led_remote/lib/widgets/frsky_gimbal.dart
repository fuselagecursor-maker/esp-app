import 'package:flutter/material.dart';

import '../theme/frsky_palette.dart';

/// FrSky-style gimbal with bronze ring, crosshairs, spring-to-center on release.
class FrSkyGimbal extends StatefulWidget {
  const FrSkyGimbal({
    super.key,
    required this.onChanged,
    this.onReleased,
    this.showCenterDetent = false,
  });

  final void Function(double x, double y) onChanged;
  final VoidCallback? onReleased;
  final bool showCenterDetent;

  @override
  State<FrSkyGimbal> createState() => _FrSkyGimbalState();
}

class _FrSkyGimbalState extends State<FrSkyGimbal> {
  Offset _knob = Offset.zero;
  bool _active = false;

  void _update(Offset local, Offset center, double radius) {
    var d = local - center;
    if (d.distance > radius) {
      d = Offset.fromDirection(d.direction, radius);
    }
    final nx = (d.dx / radius).clamp(-1.0, 1.0);
    final ny = (-d.dy / radius).clamp(-1.0, 1.0);
    setState(() {
      _knob = Offset(nx, ny);
      _active = true;
    });
    widget.onChanged(nx, ny);
  }

  void _reset() {
    setState(() {
      _knob = Offset.zero;
      _active = false;
    });
    widget.onChanged(0, 0);
    widget.onReleased?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        final side = size.shortestSide;
        final r = (side * 0.48).clamp(72.0, 160.0);
        final center = Offset(size.width / 2, size.height / 2);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (e) => _update(e.localPosition, center, r),
          onPanUpdate: (e) => _update(e.localPosition, center, r),
          onPanEnd: (_) => _reset(),
          onPanCancel: _reset,
          child: CustomPaint(
            size: size,
            painter: _FrSkyGimbalPainter(
              knob: _knob,
              active: _active,
              center: center,
              radius: r,
              showDetent: widget.showCenterDetent,
            ),
          ),
        );
      },
    );
  }
}

class _FrSkyGimbalPainter extends CustomPainter {
  _FrSkyGimbalPainter({
    required this.knob,
    required this.active,
    required this.center,
    required this.radius,
    required this.showDetent,
  });

  final Offset knob;
  final bool active;
  final Offset center;
  final double radius;
  final bool showDetent;

  @override
  void paint(Canvas canvas, Size size) {
    final sq = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: radius * 2.2, height: radius * 2.2),
      Radius.circular(6),
    );
    canvas.drawRRect(sq, Paint()..color = FrSkyPalette.gimbalWell);
    canvas.drawRRect(
      sq,
      Paint()
        ..color = const Color(0xFF0E1012)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    canvas.drawCircle(center, radius + 5, Paint()..color = const Color(0xFF3D3528));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            FrSkyPalette.bronzeHi,
            FrSkyPalette.bronzeRing,
            FrSkyPalette.bronze,
            FrSkyPalette.bronzeHi,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    final cross = Paint()
      ..color = FrSkyPalette.label.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(center.dx, center.dy - radius + 6),
      Offset(center.dx, center.dy + radius - 6),
      cross,
    );
    canvas.drawLine(
      Offset(center.dx - radius + 6, center.dy),
      Offset(center.dx + radius - 6, center.dy),
      cross,
    );

    if (showDetent) {
      canvas.drawCircle(center, 4, Paint()..color = FrSkyPalette.screenLine);
    }

    final travel = radius - 18;
    final kp = Offset(
      center.dx + knob.dx * travel,
      center.dy - knob.dy * travel,
    );

    canvas.drawCircle(
      kp,
      20,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(kp, 16, Paint()..color = const Color(0xFF1A1D20));
    canvas.drawCircle(
      kp,
      16,
      Paint()
        ..color = active ? FrSkyPalette.bronzeHi : FrSkyPalette.bronze
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < 8; i++) {
      final a = i * 3.14159 / 4;
      final p = kp + Offset.fromDirection(a - 0.78, 10);
      canvas.drawCircle(p, 2.5, Paint()..color = const Color(0xFF4A5058));
    }
    canvas.drawCircle(
      kp + const Offset(-3, -3),
      4,
      Paint()..color = Colors.white.withValues(alpha: active ? 0.35 : 0.12),
    );
  }

  @override
  bool shouldRepaint(covariant _FrSkyGimbalPainter old) =>
      old.knob != knob || old.active != active;
}
