import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../attitude_3d_math.dart';
import '../attitude_3d_motors.dart';
import '../stm32_armed_telemetry.dart';
import '../theme/attitude_3d_theme.dart';

/// Live 3D quad frame, props animated from `motorUs`, attitude from FC.
class Attitude3DView extends StatelessWidget {
  const Attitude3DView({
    super.key,
    required this.telemetry,
    required this.linkActive,
    required this.theme,
    required this.animTimeSec,
    this.lastUpdate,
    this.demoMode = false,
  });

  final Stm32ArmedTelemetry telemetry;
  final bool linkActive;
  final Attitude3DTheme theme;
  final double animTimeSec;
  final DateTime? lastUpdate;
  final bool demoMode;

  @override
  Widget build(BuildContext context) {
    final roll = telemetry.attRollDeg ?? 0.0;
    final pitch = telemetry.attPitchDeg ?? 0.0;
    final yaw = telemetry.yawDeg ?? 0.0;
    final stale = demoMode ? false : _isStale();
    final motorUs = Attitude3DMotors.normalizeUs(telemetry.motorUs);
    final motorsLive =
        demoMode || (linkActive && !stale && telemetry.hasMotors);
    final telemetryLive =
        demoMode || (linkActive && !stale && telemetry.hasAttitude);

    return LayoutBuilder(
      builder: (context, c) {
        return CustomPaint(
          size: Size(c.maxWidth, c.maxHeight),
          painter: _Attitude3DPainter(
            rollDeg: roll,
            pitchDeg: pitch,
            yawDeg: yaw,
            motorUs: motorUs,
            animTimeSec: animTimeSec,
            theme: theme,
            espLinked: linkActive,
            telemetryLive: telemetryLive,
            motorsLive: motorsLive,
            hasAttitude: telemetry.hasAttitude,
            isLiveLine: telemetry.isLiveLine,
            demoMode: demoMode,
          ),
        );
      },
    );
  }

  bool _isStale() {
    if (!linkActive) return true;
    final at = lastUpdate;
    if (at == null) return true;
    final limit = telemetry.isLiveLine ? 1200 : 2800;
    return DateTime.now().difference(at).inMilliseconds > limit;
  }
}

class _Attitude3DPainter extends CustomPainter {
  _Attitude3DPainter({
    required this.rollDeg,
    required this.pitchDeg,
    required this.yawDeg,
    required this.motorUs,
    required this.animTimeSec,
    required this.theme,
    required this.espLinked,
    required this.telemetryLive,
    required this.motorsLive,
    required this.hasAttitude,
    required this.isLiveLine,
    required this.demoMode,
  });

  final double rollDeg;
  final double pitchDeg;
  final double yawDeg;
  final List<int> motorUs;
  final double animTimeSec;
  final Attitude3DTheme theme;
  final bool espLinked;
  final bool telemetryLive;
  final bool motorsLive;
  final bool hasAttitude;
  final bool isLiveLine;
  final bool demoMode;

  static const _worldX = Color(0xFFEF4444);
  static const _worldY = Color(0xFF22C55E);
  static const _worldZ = Color(0xFF3B82F6);
  static const _bodyX = Color(0xFFFF6B6B);
  static const _bodyY = Color(0xFF4ADE80);
  static const _bodyZ = Color(0xFF60A5FA);
  static const _frame = Color(0xFFCBD5E1);
  static const _motorIdle = Color(0xFF94A3B8);
  static const _motorSpin = Color(0xFF4ADE80);
  static const _propBlade = Color(0xFFE2E8F0);

  Vec3 _w(Vec3 local) => Attitude3DMath.bodyToWorld(
        local,
        rollDeg: rollDeg,
        pitchDeg: pitchDeg,
        yawDeg: yawDeg,
      );

  Offset _p(Vec3 world, double cx, double cy, double scale) {
    final pr = Attitude3DMath.project(world, scale);
    return Offset(cx + pr.dx, cy + pr.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.52;
    final scale = math.min(size.width, size.height) * 0.24;
    final dim = !telemetryLive;

    _drawGrid(canvas, cx, cy, scale);
    _drawLevelHorizon(canvas, cx, cy, scale);
    _drawBodyDeck(canvas, cx, cy, scale, dimmed: dim);
    _drawDroneFrame(canvas, cx, cy, scale, dimmed: dim);
    _drawPropellers(canvas, cx, cy, scale, dimmed: dim || !motorsLive);

    const worldAxes = [
      (Vec3(1, 0, 0), _worldX, 'X'),
      (Vec3(0, 1, 0), _worldY, 'Y'),
      (Vec3(0, 0, 1), _worldZ, 'Z'),
    ];
    for (final (axis, color, label) in worldAxes) {
      _drawAxis(
        canvas,
        cx,
        cy,
        scale,
        Vec3.zero,
        axis * Attitude3DMath.axisLength,
        color.withValues(alpha: 0.22),
        label,
        dashed: true,
        prefix: 'W',
        strokeWidth: 1.2,
      );
    }

    final body = Attitude3DMath.bodyAxesWorld(
      rollDeg: rollDeg,
      pitchDeg: pitchDeg,
      yawDeg: yawDeg,
    );
    const labels = ['X', 'Y', 'Z'];
    const colors = [_bodyX, _bodyY, _bodyZ];
    for (var i = 0; i < 3; i++) {
      _drawAxis(
        canvas,
        cx,
        cy,
        scale,
        Vec3.zero,
        body[i] * Attitude3DMath.axisLength,
        colors[i].withValues(alpha: dim ? 0.4 : 0.85),
        labels[i],
        prefix: 'B',
        strokeWidth: dim ? 2.0 : 2.6,
      );
    }

    _drawLegend(canvas, size);
    _drawTiltReadout(canvas, size);
  }

  void _drawLevelHorizon(Canvas canvas, double cx, double cy, double scale) {
    final ring = Attitude3DMath.levelHorizonRing();
    final path = Path();
    for (var i = 0; i < ring.length; i++) {
      final pt = _p(ring[i], cx, cy, scale);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = theme.isLight
            ? const Color(0xFF94A3B8).withValues(alpha: 0.35)
            : const Color(0xFF64748B).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawLine(
      _p(const Vec3(-1.05, 0, 0), cx, cy, scale),
      _p(const Vec3(1.05, 0, 0), cx, cy, scale),
      Paint()
        ..color = theme.isLight
            ? const Color(0xFF64748B).withValues(alpha: 0.5)
            : const Color(0xFF94A3B8).withValues(alpha: 0.45)
        ..strokeWidth = 1.2,
    );
  }

  void _drawBodyDeck(
    Canvas canvas,
    double cx,
    double cy,
    double scale, {
    required bool dimmed,
  }) {
    final deck = Attitude3DMath.quadDeck();
    final hub = _p(_w(Vec3.zero), cx, cy, scale);
    final path = Path()..moveTo(hub.dx, hub.dy);
    for (final tip in deck) {
      final pt = _p(_w(tip), cx, cy, scale);
      path.lineTo(pt.dx, pt.dy);
    }
    path.close();

    final level = Attitude3DMath.isNearLevel(rollDeg, pitchDeg);
    final fill = level
        ? (theme.isLight ? const Color(0xFF22C55E) : const Color(0xFF4ADE80))
        : (theme.isLight ? const Color(0xFFF59E0B) : const Color(0xFFFBBF24));
    canvas.drawPath(
      path,
      Paint()..color = fill.withValues(alpha: dimmed ? 0.1 : 0.2),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = fill.withValues(alpha: dimmed ? 0.3 : 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawDroneFrame(Canvas canvas, double cx, double cy, double scale,
      {required bool dimmed}) {
    final frameColor = dimmed ? _frame.withValues(alpha: 0.45) : _frame;
    final armWidth = dimmed ? 3.0 : 4.2;

    final hub = _p(_w(Vec3.zero), cx, cy, scale);
    canvas.drawCircle(
      hub,
      7,
      Paint()..color = frameColor.withValues(alpha: 0.95),
    );
    canvas.drawCircle(
      hub,
      7,
      Paint()
        ..color = theme.hubStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    var motorIndex = 0;
    for (final arm in Attitude3DMath.quadArms()) {
      final us = motorUs[motorIndex];
      final activity = Attitude3DMotors.activity(us);
      final motorColor = Color.lerp(
        dimmed ? _motorIdle.withValues(alpha: 0.45) : _motorIdle,
        dimmed ? _motorSpin.withValues(alpha: 0.55) : _motorSpin,
        activity,
      )!;

      final a0 = _p(_w(arm.from), cx, cy, scale);
      final a1 = _p(_w(arm.to), cx, cy, scale);
      canvas.drawLine(
        a0,
        a1,
        Paint()
          ..color = frameColor
          ..strokeWidth = armWidth
          ..strokeCap = StrokeCap.round,
      );

      final motorR = 8.0 + activity * 4.0;
      canvas.drawCircle(a1, motorR, Paint()..color = motorColor);
      canvas.drawCircle(
        a1,
        motorR,
        Paint()
          ..color = theme.motorStroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      motorIndex++;
    }

    final nose = Attitude3DMath.noseMarker();
    final noseWorld = nose.map(_w).toList();
    final path = Path();
    for (var i = 0; i < noseWorld.length; i++) {
      final pt = _p(noseWorld[i], cx, cy, scale);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = _bodyX.withValues(alpha: dimmed ? 0.45 : 0.9),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _bodyX.withValues(alpha: dimmed ? 0.55 : 1.0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _drawPropellers(
    Canvas canvas,
    double cx,
    double cy,
    double scale, {
    required bool dimmed,
  }) {
    final tips = Attitude3DMath.motorTips();
    for (var i = 0; i < 4; i++) {
      final us = motorUs[i];
      final center = _p(_w(tips[i]), cx, cy, scale);
      final spin = demoMode
          ? 24.0 + Attitude3DMotors.activity(us) * 8.0
          : Attitude3DMotors.spinRadPerSec(us);
      final dir = Attitude3DMotors.spinDirections[i];
      final angle = animTimeSec * spin * dir;
      final activity = Attitude3DMotors.activity(us);
      final bladeLen = 11.0 + activity * 10.0;
      final alpha = dimmed ? 0.25 : (0.35 + activity * 0.55);

      if (spin <= 0.01) {
        canvas.drawLine(
          Offset(center.dx - 6, center.dy),
          Offset(center.dx + 6, center.dy),
          Paint()
            ..color = _propBlade.withValues(alpha: alpha * 0.6)
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
        continue;
      }

      for (final base in [0.0, math.pi / 2]) {
        final a = angle + base;
        final dx = math.cos(a) * bladeLen;
        final dy = math.sin(a) * bladeLen;
        canvas.drawLine(
          Offset(center.dx - dx, center.dy - dy),
          Offset(center.dx + dx, center.dy + dy),
          Paint()
            ..color = _propBlade.withValues(alpha: alpha)
            ..strokeWidth = 2.0 + activity * 1.5
            ..strokeCap = StrokeCap.round,
        );
      }

      if (activity > 0.15) {
        canvas.drawCircle(
          center,
          3 + activity * 2,
          Paint()..color = _motorSpin.withValues(alpha: alpha * 0.35),
        );
      }
    }
  }

  void _drawGrid(Canvas canvas, double cx, double cy, double scale) {
    final p = Paint()
      ..color = theme.grid
      ..strokeWidth = 0.6;
    for (var i = -2; i <= 2; i++) {
      if (i == 0) continue;
      final t = i * 0.35;
      final a = Attitude3DMath.project(Vec3(t, 0, -2), scale);
      final b = Attitude3DMath.project(Vec3(t, 0, 2), scale);
      canvas.drawLine(Offset(cx + a.dx, cy + a.dy), Offset(cx + b.dx, cy + b.dy), p);
      final c = Attitude3DMath.project(Vec3(-2, 0, t), scale);
      final d = Attitude3DMath.project(Vec3(2, 0, t), scale);
      canvas.drawLine(Offset(cx + c.dx, cy + c.dy), Offset(cx + d.dx, cy + d.dy), p);
    }
  }

  void _drawAxis(
    Canvas canvas,
    double cx,
    double cy,
    double scale,
    Vec3 from,
    Vec3 to,
    Color color,
    String label, {
    String prefix = '',
    bool dashed = false,
    double strokeWidth = 2,
  }) {
    final a = Attitude3DMath.project(from, scale);
    final b = Attitude3DMath.project(to, scale);
    final p0 = Offset(cx + a.dx, cy + a.dy);
    final p1 = Offset(cx + b.dx, cy + b.dy);

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    if (dashed) {
      _drawDashedLine(canvas, p0, p1, paint);
    } else {
      canvas.drawLine(p0, p1, paint);
    }
    _drawArrowHead(canvas, p0, p1, color);

    final tp = TextPainter(
      text: TextSpan(
        text: prefix.isEmpty ? label : '$prefix$label',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p1 + Offset(4, -tp.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    final d = b - a;
    final len = d.distance;
    if (len < 1) return;
    final dir = d / len;
    var pos = 0.0;
    while (pos < len) {
      final end = math.min(pos + dash, len);
      canvas.drawLine(a + dir * pos, a + dir * end, paint);
      pos += dash + gap;
    }
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Color color) {
    final d = to - from;
    if (d.distance < 8) return;
    final dir = d / d.distance;
    final left = Offset(-dir.dy, dir.dx);
    final tip = to;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - dir.dx * 10 + left.dx * 4, tip.dy - dir.dy * 10 + left.dy * 4)
      ..lineTo(tip.dx - dir.dx * 10 - left.dx * 4, tip.dy - dir.dy * 10 - left.dy * 4)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawLegend(Canvas canvas, Size size) {
    final status = !espLinked
        ? 'NO LINK — preview only'
        : !telemetryLive
            ? 'WAITING for attR/attP…'
            : (isLiveLine ? 'LIVE 10Hz' : 'LIVE 2Hz');
    final statusColor = telemetryLive
        ? (theme.isLight ? const Color(0xFF15803D) : const Color(0xFF4ADE80))
        : theme.legendMuted;

    final avgUs = motorUs.isEmpty
        ? 0
        : motorUs.reduce((a, b) => a + b) ~/ motorUs.length;

    final lines = [
      ('Gray ring = level ground', theme.legendMuted),
      ('Props spin ∝ us= (M1–M4)', theme.legendBody),
      ('Motors: ${Attitude3DMotors.formatUsList(motorUs)}', theme.legendBody),
      (status, statusColor),
    ];
    var y = 12.0;
    for (final (text, color) in lines) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.55);
      tp.paint(canvas, Offset(12, y));
      y += 13;
    }

    if (motorsLive && avgUs > Attitude3DMotors.armIdleUs) {
      final spinLabel = TextPainter(
        text: TextSpan(
          text: 'SPINNING',
          style: TextStyle(
            color: theme.isLight ? const Color(0xFF15803D) : const Color(0xFF4ADE80),
            fontSize: 8,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      spinLabel.paint(canvas, Offset(12, y));
    }
  }

  void _drawTiltReadout(Canvas canvas, Size size) {
    if (!hasAttitude) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'Roll —   Pitch —\nNO FC ATTITUDE',
          style: TextStyle(
            color: theme.legendMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
            height: 1.35,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 14, size.height - 52));
      return;
    }

    final level = Attitude3DMath.isNearLevel(rollDeg, pitchDeg);
    final levelColor = level
        ? (theme.isLight ? const Color(0xFF15803D) : const Color(0xFF4ADE80))
        : (theme.isLight ? const Color(0xFFB45309) : const Color(0xFFFBBF24));

    final lines = [
      (
        'Roll ${rollDeg.toStringAsFixed(1)}°   Pitch ${pitchDeg.toStringAsFixed(1)}°',
        theme.legendBody,
        13.0,
        FontWeight.w700,
      ),
      (
        level ? 'LEVEL' : 'TILTED',
        levelColor,
        11.0,
        FontWeight.w800,
      ),
    ];

    var y = size.height - 52;
    for (final (text, color, fs, weight) in lines) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fs,
            fontWeight: weight,
            fontFamily: 'monospace',
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 14, y));
      y += fs + 6;
    }
  }

  @override
  bool shouldRepaint(covariant _Attitude3DPainter old) =>
      old.rollDeg != rollDeg ||
      old.pitchDeg != pitchDeg ||
      old.yawDeg != yawDeg ||
      old.animTimeSec != animTimeSec ||
      old.theme != theme ||
      old.espLinked != espLinked ||
      old.telemetryLive != telemetryLive ||
      old.motorsLive != motorsLive ||
      old.demoMode != demoMode ||
      !_sameMotors(old.motorUs, motorUs);

  static bool _sameMotors(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
