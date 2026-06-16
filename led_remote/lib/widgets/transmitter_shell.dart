import 'package:flutter/material.dart';

/// FrSky-style mechanical handset background (bronze gimbals, recessed screen).
class TransmitterShellPainter extends CustomPainter {
  const TransmitterShellPainter({this.landscape = true});

  final bool landscape;

  static const _bronze = Color(0xFF9A7B4F);
  static const _bronzeLight = Color(0xFFC9A227);
  static const _bodyDark = Color(0xFF1E2328);
  static const _bodyMid = Color(0xFF2A3036);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, 4, w - 8, h - 8),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bodyMid, _bodyDark, const Color(0xFF14181C)],
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0xFF4A5560)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Shoulder screws (decorative)
    for (final dx in [24.0, w - 24]) {
      for (final dy in [18.0, h - 18]) {
        _drawScrew(canvas, Offset(dx, dy));
      }
    }

    // Bottom LCD bezel (Horus-style screen at bottom centre)
    final screenW = landscape ? w * 0.36 : w * 0.55;
    final screenH = landscape ? 52.0 : 44.0;
    final screenY = landscape ? h * 0.72 : h * 0.12;
    final screenRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w / 2, screenY),
        width: screenW,
        height: screenH,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(screenRect, Paint()..color = const Color(0xFF0A0C0E));
    canvas.drawRRect(
      screenRect,
      Paint()
        ..color = _bronze.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Orange status line inside screen
    canvas.drawLine(
      Offset(w / 2 - screenW / 2 + 8, screenY - screenH / 2 + 10),
      Offset(w / 2 + screenW / 2 - 8, screenY - screenH / 2 + 10),
      Paint()
        ..color = const Color(0xFFE86C00)
        ..strokeWidth = 2,
    );

    // Gimbal positions — left / right, vertically centred in landscape
    final stickY = landscape ? h * 0.42 : h * 0.58;
    final stickR = landscape ? h * 0.28 : w * 0.22;
    _drawGimbalAssembly(canvas, Offset(w * 0.22, stickY), stickR.clamp(56.0, 110.0));
    _drawGimbalAssembly(canvas, Offset(w * 0.78, stickY), stickR.clamp(56.0, 110.0));

    // Trim slider hints (vertical bars beside gimbals)
    _drawTrimChannel(canvas, Rect.fromLTWH(w * 0.08, stickY - 40, 8, 80));
    _drawTrimChannel(canvas, Rect.fromLTWH(w * 0.92 - 8, stickY - 40, 8, 80));

    // Top toggle hints
    _drawToggleHint(canvas, Offset(w * 0.12, 28));
    _drawToggleHint(canvas, Offset(w * 0.88, 28));
  }

  void _drawScrew(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 5, Paint()..color = const Color(0xFF3A4248));
    canvas.drawCircle(
      c,
      5,
      Paint()
        ..color = const Color(0xFF5C6A72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final slot = Paint()
      ..color = const Color(0xFF15181C)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(c.dx - 3, c.dy), Offset(c.dx + 3, c.dy), slot);
  }

  void _drawGimbalAssembly(Canvas canvas, Offset center, double radius) {
    // Square recess
    final sq = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: radius * 2.35,
        height: radius * 2.35,
      ),
      Radius.circular(radius * 0.12),
    );
    canvas.drawRRect(sq, Paint()..color = const Color(0xFF12161A));
    canvas.drawRRect(
      sq,
      Paint()
        ..color = const Color(0xFF0A0C0E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Bronze outer ring
    canvas.drawCircle(
      center,
      radius + 6,
      Paint()
        ..color = _bronze.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFF252A2F),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            _bronzeLight.withValues(alpha: 0.9),
            _bronze,
            _bronzeLight.withValues(alpha: 0.7),
            _bronze,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    // Inner shadow ring
    canvas.drawCircle(
      center,
      radius * 0.55,
      Paint()
        ..color = const Color(0xFF15191D).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawTrimChannel(Canvas canvas, Rect r) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(3)),
      Paint()..color = const Color(0xFF15181C),
    );
    canvas.drawLine(
      Offset(r.left + r.width / 2, r.top + r.height * 0.5),
      Offset(r.left + r.width / 2, r.bottom - 4),
      Paint()
        ..color = _bronzeLight.withValues(alpha: 0.6)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawToggleHint(Canvas canvas, Offset c) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 28, height: 14),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF2A3238),
    );
    canvas.drawCircle(
      Offset(c.dx + 6, c.dy),
      5,
      Paint()..color = _bronzeLight.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(covariant TransmitterShellPainter old) =>
      old.landscape != landscape;
}
