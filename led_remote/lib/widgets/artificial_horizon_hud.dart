import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../stm32_telemetry.dart';
import '../theme/tx_palette.dart';

/// Mini attitude HUD — matches machined transmitter palette (TxPalette).
class ArtificialHorizonHud extends StatelessWidget {
  const ArtificialHorizonHud({
    super.key,
    required this.snapshot,
    required this.linkActive,
    this.lastUpdate,
    this.appArmed = false,
    this.width = 248,
    this.height = 200,
    this.compact = false,
  });

  final FcTelemetrySnapshot? snapshot;
  final bool linkActive;
  final DateTime? lastUpdate;
  final bool appArmed;
  final double width;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
    final roll = snap?.displayRollDeg ?? 0;
    final pitch = snap?.displayPitchDeg ?? 0;
    final yaw = snap?.displayYawDeg ?? 0;
    final fcArmed = snap?.armed;
    final showDisarmed = fcArmed == false || (fcArmed == null && !appArmed);
    final showArmed = fcArmed == true || (fcArmed == null && appArmed);
    final stale = _isStale();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: TxPalette.matteCap,
          borderRadius: BorderRadius.circular(compact ? 4 : 6),
          border: Border.all(
            color: stale
                ? TxPalette.labelMuted.withValues(alpha: 0.45)
                : TxPalette.engraved,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: compact ? 0.35 : 0.5),
              blurRadius: compact ? 2 : 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _HorizonPainter(
            rollDeg: roll,
            pitchDeg: pitch,
            yawDeg: yaw,
            snapshot: snap,
            linkActive: linkActive,
            showDisarmed: showDisarmed && !showArmed,
            showArmed: showArmed,
            stale: stale,
            hasTelemetry: snap?.hasData ?? false,
            compact: compact,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  bool _isStale() {
    if (!linkActive) return true;
    final at = lastUpdate;
    if (at == null) return true;
    return DateTime.now().difference(at).inSeconds > 4;
  }
}

class _HorizonPainter extends CustomPainter {
  _HorizonPainter({
    required this.rollDeg,
    required this.pitchDeg,
    required this.yawDeg,
    required this.snapshot,
    required this.linkActive,
    required this.showDisarmed,
    required this.showArmed,
    required this.stale,
    required this.hasTelemetry,
    required this.compact,
  });

  final double rollDeg;
  final double pitchDeg;
  final double yawDeg;
  final FcTelemetrySnapshot? snapshot;
  final bool linkActive;
  final bool showDisarmed;
  final bool showArmed;
  final bool stale;
  final bool hasTelemetry;
  final bool compact;

  // Attitude bands — muted, same family as TxPalette.panel
  static const _sky = Color(0xFF2C343C);
  static const _ground = Color(0xFF242018);
  static const _lineHi = Color(0xFFC07010);
  static const _lineDim = Color(0xFF5A5040);
  static const _textHi = Color(0xFFB8A898);
  static const _safeTint = Color(0xFF9A7068);

  @override
  void paint(Canvas canvas, Size size) {
    final headH = compact ? 13.0 : 20.0;
    final footH = compact ? 11.0 : 34.0;
    final innerTop = headH;
    final innerBottom = size.height - footH;
    final innerH = innerBottom - innerTop;
    final innerCenter = Offset(size.width * 0.5, innerTop + innerH * 0.5);
    final pxPerDeg = innerH / (compact ? 38 : 65);

    canvas.drawRect(Offset.zero & size, Paint()..color = TxPalette.recess);

    if (!compact) {
      _drawHeadingTape(canvas, size, headH);
      _drawRollIndicator(canvas, size);
    } else {
      _drawHeadingTape(canvas, size, headH, mini: true);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, innerTop, size.width, innerH));

    canvas.save();
    canvas.translate(innerCenter.dx, innerCenter.dy);
    canvas.rotate(rollDeg * math.pi / 180);
    canvas.translate(0, pitchDeg * pxPerDeg);

    _drawSkyGround(canvas, size, pxPerDeg);
    _drawPitchLadder(canvas, pxPerDeg, size.width, step: compact ? 20 : 10);

    canvas.restore();
    canvas.restore();

    _drawAircraft(canvas, innerCenter);
    _drawStatusBanner(canvas, size);
    if (!compact) {
      _drawSideReadouts(canvas, size);
      _drawFooter(canvas, size, footH);
    } else {
      _drawFooter(canvas, size, footH, mini: true);
    }
  }

  void _drawHeadingTape(
    Canvas canvas,
    Size size,
    double headH, {
    bool mini = false,
  }) {
    final heading = ((yawDeg % 360) + 360) % 360;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, headH),
      Paint()..color = TxPalette.panelDeep,
    );
    canvas.drawLine(
      Offset(0, headH),
      Offset(size.width, headH),
      Paint()
        ..color = TxPalette.engraved
        ..strokeWidth = 1,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: heading.round().toString().padLeft(3, '0'),
        style: TextStyle(
          color: TxPalette.amber,
          fontSize: mini ? 8 : 13,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          letterSpacing: mini ? 1 : 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, mini ? 2 : 3));

    if (mini) return;

    final tickPaint = Paint()
      ..color = _lineDim
      ..strokeWidth = 1;
    for (var d = -2; d <= 2; d++) {
      final deg = (heading + d * 15).round() % 360;
      final x = size.width * 0.5 + d * 28.0;
      canvas.drawLine(Offset(x, headH - 4), Offset(x, headH), tickPaint);
      if (d == 0) continue;
      final lbl = TextPainter(
        text: TextSpan(
          text: '$deg',
          style: const TextStyle(
            color: _lineDim,
            fontSize: 7,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      lbl.paint(canvas, Offset(x - lbl.width / 2, 8));
    }
  }

  void _drawRollIndicator(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    const cy = 24.0;
    const r = 52.0;
    final arcRect = Rect.fromCircle(center: Offset(cx, cy + r * 0.3), radius: r);

    canvas.drawArc(
      arcRect,
      math.pi * 1.15,
      math.pi * 0.7,
      false,
      Paint()
        ..color = _lineDim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final rollRad = (rollDeg - 90) * math.pi / 180;
    final tip = Offset(
      cx + (r - 2) * math.cos(rollRad),
      cy + r * 0.3 + (r - 2) * math.sin(rollRad),
    );
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 5 * math.cos(rollRad + math.pi / 2),
          tip.dy - 5 * math.sin(rollRad + math.pi / 2))
      ..lineTo(tip.dx - 5 * math.cos(rollRad - math.pi / 2),
          tip.dy - 5 * math.sin(rollRad - math.pi / 2))
      ..close();
    canvas.drawPath(path, Paint()..color = TxPalette.amber);
  }

  void _drawSkyGround(Canvas canvas, Size size, double pxPerDeg) {
    final extent = math.max(size.width, size.height) * 2.5;
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: extent, height: extent),
      Paint()..color = _sky,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(0, extent * 0.25),
        width: extent,
        height: extent,
      ),
      Paint()..color = _ground,
    );
    canvas.drawLine(
      Offset(-extent, 0),
      Offset(extent, 0),
      Paint()
        ..color = _lineHi
        ..strokeWidth = compact ? 1.2 : 2,
    );
  }

  void _drawPitchLadder(
    Canvas canvas,
    double pxPerDeg,
    double width, {
    int step = 10,
  }) {
    final paint = Paint()
      ..color = _lineDim.withValues(alpha: 0.85)
      ..strokeWidth = 1;

    for (var deg = -30; deg <= 30; deg += step) {
      if (deg == 0) continue;
      final y = -deg * pxPerDeg;
      final half = width * (deg.abs() >= 20 ? 0.34 : 0.24);
      final gap = deg.abs() >= 20 ? 5.0 : 0.0;
      if (gap > 0) {
        canvas.drawLine(Offset(-half, y), Offset(-gap, y), paint);
        canvas.drawLine(Offset(gap, y), Offset(half, y), paint);
      } else {
        canvas.drawLine(Offset(-half, y), Offset(half, y), paint);
      }
    }
  }

  void _drawAircraft(Canvas canvas, Offset center) {
    final w = compact ? 12.0 : 22.0;
    final h = compact ? 6.0 : 10.0;
    final paint = Paint()
      ..color = TxPalette.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 1.4 : 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(center.dx - w, center.dy + h * 0.5)
      ..lineTo(center.dx, center.dy - h)
      ..lineTo(center.dx + w, center.dy + h * 0.5);
    if (!compact) {
      path
        ..moveTo(center.dx - w * 0.45, center.dy + 2)
        ..lineTo(center.dx + w * 0.45, center.dy + 2);
    }
    canvas.drawPath(path, paint);
  }

  void _drawStatusBanner(Canvas canvas, Size size) {
    if (!showDisarmed && !showArmed) return;

    final label = showArmed ? 'ARM' : 'SAFE';
    final color = showArmed ? TxPalette.armLed : _safeTint;
    final fs = compact ? 8.0 : 18.0;

    final tp = TextPainter(
      text: TextSpan(
        text: compact ? label : (showArmed ? 'ARMED' : 'DISARMED'),
        style: TextStyle(
          color: color,
          fontSize: fs,
          fontWeight: FontWeight.w800,
          letterSpacing: compact ? 1.5 : 3,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        (size.width - tp.width) / 2,
        size.height * (compact ? 0.36 : 0.44),
      ),
    );
  }

  void _drawSideReadouts(Canvas canvas, Size size) {
    final snap = snapshot;
    final style = const TextStyle(
      color: _textHi,
      fontSize: 8,
      fontFamily: 'monospace',
      height: 1.35,
    );
    final dim = style.copyWith(color: _lineDim, fontSize: 7);

    void column(double x, List<String> lines, {bool right = false}) {
      var y = 28.0;
      for (final line in lines) {
        final tp = TextPainter(
          text: TextSpan(
            text: line,
            style: line.startsWith(' ') ? dim : style,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(right ? x - tp.width : x, y));
        y += 11;
      }
    }

    column(6, [
      ' spP ${snap?.formatNum(snap.setpointPitchDps) ?? "—"}',
      ' spR ${snap?.formatNum(snap.setpointRollDps) ?? "—"}',
      ' R  ${snap?.formatNum(snap?.rollDeg, decimals: 1) ?? "—"}',
    ]);
    column(size.width - 6, [
      ' spY ${snap?.formatNum(snap?.setpointYawDps) ?? "—"}',
      ' THR ${snap?.throttlePercent?.toString() ?? "—"}',
      ' P  ${snap?.formatNum(snap?.pitchDeg, decimals: 1) ?? "—"}',
    ], right: true);
  }

  void _drawFooter(Canvas canvas, Size size, double footH, {bool mini = false}) {
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - footH, size.width, footH),
      Paint()..color = TxPalette.panelDeep,
    );
    canvas.drawLine(
      Offset(0, size.height - footH),
      Offset(size.width, size.height - footH),
      Paint()
        ..color = TxPalette.engraved
        ..strokeWidth = 1,
    );

    final linkColor = !linkActive
        ? _lineDim
        : stale
            ? TxPalette.labelMuted
            : TxPalette.armLed;
    final label = mini
        ? (linkActive ? (stale ? '··' : '●') : '—')
        : '${hasTelemetry ? 'RATE' : (linkActive ? 'LINK' : 'OFF')}  ${stale ? 'stale' : 'live'}';

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: mini ? linkColor : _textHi,
          fontSize: mini ? 7 : 8,
          fontFamily: 'monospace',
          letterSpacing: mini ? 0 : 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        (size.width - tp.width) / 2,
        size.height - footH + (mini ? 2 : 12),
      ),
    );

    if (!mini) {
      final sub = TextPainter(
        text: const TextSpan(
          text: 'AS 0.0  GS 0.0',
          style: TextStyle(
            color: _lineDim,
            fontSize: 8,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      sub.paint(canvas, Offset(6, size.height - footH + 12));
    }
  }

  @override
  bool shouldRepaint(covariant _HorizonPainter old) =>
      old.rollDeg != rollDeg ||
      old.pitchDeg != pitchDeg ||
      old.yawDeg != yawDeg ||
      old.snapshot != snapshot ||
      old.linkActive != linkActive ||
      old.showDisarmed != showDisarmed ||
      old.showArmed != showArmed ||
      old.stale != stale ||
      old.compact != compact;
}
