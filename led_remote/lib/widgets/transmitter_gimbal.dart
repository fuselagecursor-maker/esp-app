import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tx_palette.dart';

/// Recessed gimbal well — 130/96 rings, crosshair, matte cap with grip ridges.
class TransmitterGimbal extends StatefulWidget {
  const TransmitterGimbal({
    super.key,
    required this.onChanged,
    this.onReleased,
    this.showCenterDetent = false,
    this.throttleFromBottom = false,
    this.holdThrottleOnRelease = false,
  });

  final void Function(double x, double y) onChanged;
  final VoidCallback? onReleased;
  final bool showCenterDetent;

  /// Paint bottom detent (armed throttle axis).
  final bool throttleFromBottom;

  /// When true (armed left stick): release keeps throttle Y; yaw X returns to center.
  final bool holdThrottleOnRelease;

  @override
  State<TransmitterGimbal> createState() => _TransmitterGimbalState();
}

class _TransmitterGimbalState extends State<TransmitterGimbal> {
  static const _bottomStick = Offset(0, -1);

  Offset _knob = Offset.zero;
  int? _activePointer;

  @override
  void initState() {
    super.initState();
    if (widget.holdThrottleOnRelease) _knob = _bottomStick;
  }

  @override
  void didUpdateWidget(TransmitterGimbal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.holdThrottleOnRelease && !oldWidget.holdThrottleOnRelease) {
      setState(() => _knob = _bottomStick);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onChanged(0, -1);
      });
    } else if (!widget.holdThrottleOnRelease && oldWidget.holdThrottleOnRelease) {
      setState(() => _knob = Offset.zero);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onChanged(0, 0);
      });
    }
  }

  void _update(Offset local, Offset center, double travel) {
    var d = local - center;
    if (d.distance > travel) {
      d = Offset.fromDirection(d.direction, travel);
    }
    final nx = (d.dx / travel).clamp(-1.0, 1.0);
    final ny = (-d.dy / travel).clamp(-1.0, 1.0);

    setState(() => _knob = Offset(nx, ny));
    widget.onChanged(nx, ny);
  }

  void _reset() {
    _activePointer = null;
    if (widget.holdThrottleOnRelease) {
      setState(() => _knob = Offset(0, _knob.dy));
      widget.onChanged(0, _knob.dy);
    } else {
      setState(() => _knob = Offset.zero);
      widget.onChanged(0, 0);
    }
    widget.onReleased?.call();
  }

  void _onPointerDown(PointerDownEvent e, Offset center, double travel) {
    if (_activePointer != null) return;
    _activePointer = e.pointer;
    _update(e.localPosition, center, travel);
  }

  void _onPointerMove(PointerMoveEvent e, Offset center, double travel) {
    if (e.pointer != _activePointer) return;
    _update(e.localPosition, center, travel);
  }

  void _onPointerEnd(PointerEvent e, Offset center, double travel) {
    if (e.pointer != _activePointer) return;
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.min(c.maxWidth, c.maxHeight);
        final outerR = (side * 0.48).clamp(68.0, 92.0);
        final innerR = outerR * (96 / 130);
        final center = Offset(c.maxWidth / 2, c.maxHeight / 2);
        final travel = innerR - 16;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _onPointerDown(e, center, travel),
          onPointerMove: (e) => _onPointerMove(e, center, travel),
          onPointerUp: (e) => _onPointerEnd(e, center, travel),
          onPointerCancel: (e) => _onPointerEnd(e, center, travel),
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _GimbalPainter(
              center: center,
              outerR: outerR,
              innerR: innerR,
              knob: _knob,
              travel: travel,
              showDetent: widget.showCenterDetent,
              highlightBottom: widget.throttleFromBottom,
            ),
          ),
        );
      },
    );
  }
}

class _GimbalPainter extends CustomPainter {
  _GimbalPainter({
    required this.center,
    required this.outerR,
    required this.innerR,
    required this.knob,
    required this.travel,
    required this.showDetent,
    required this.highlightBottom,
  });

  final Offset center;
  final double outerR;
  final double innerR;
  final Offset knob;
  final double travel;
  final bool showDetent;
  final bool highlightBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final well = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: outerR * 2.35,
        height: outerR * 2.35,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(well, Paint()..color = TxPalette.recess);
    _crosshatch(canvas, well.outerRect.deflate(4));

    canvas.drawRRect(
      well,
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    _ring(canvas, center, outerR, 2);
    _ring(canvas, center, innerR, 1.2);

    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final p0 = center + Offset.fromDirection(a, innerR - 4);
      final p1 = center + Offset.fromDirection(a, innerR + 5);
      canvas.drawLine(
        p0,
        p1,
        Paint()
          ..color = TxPalette.labelMuted
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.square,
      );
    }

    final hair = Paint()
      ..color = TxPalette.engraved.withValues(alpha: 0.85)
      ..strokeWidth = 0.6;
    canvas.drawLine(
      Offset(center.dx, center.dy - innerR + 8),
      Offset(center.dx, center.dy + innerR - 8),
      hair,
    );
    canvas.drawLine(
      Offset(center.dx - innerR + 8, center.dy),
      Offset(center.dx + innerR - 8, center.dy),
      hair,
    );

    if (showDetent) {
      canvas.drawCircle(
        center,
        2,
        Paint()..color = TxPalette.amber.withValues(alpha: 0.7),
      );
    }

    if (highlightBottom) {
      final bottomMark = center + Offset(0, innerR - 6);
      canvas.drawCircle(
        bottomMark,
        3,
        Paint()..color = TxPalette.amber.withValues(alpha: 0.85),
      );
    }

    final kp = Offset(
      center.dx + knob.dx * travel,
      center.dy - knob.dy * travel,
    );
    _stickCap(canvas, kp);
  }

  void _crosshatch(Canvas canvas, Rect r) {
    final p = Paint()
      ..color = TxPalette.engraved.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    const step = 7.0;
    for (var x = r.left; x < r.right; x += step) {
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), p);
    }
    for (var y = r.top; y < r.bottom; y += step) {
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), p);
    }
  }

  void _ring(Canvas canvas, Offset c, double r, double w) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
    );
    canvas.drawCircle(
      c,
      r - w,
      Paint()
        ..color = TxPalette.panelDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  void _stickCap(Canvas canvas, Offset kp) {
    final capR = innerR * 0.17;
    canvas.drawCircle(kp, capR + 1, Paint()..color = const Color(0xFF0A0C0E));
    canvas.drawCircle(kp, capR, Paint()..color = TxPalette.matteCap);

    final tab = Paint()..color = const Color(0xFF2C3034);
    const tw = 5.0;
    const th = 4.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: kp + Offset(0, -capR + 2), width: tw, height: th),
        const Radius.circular(1),
      ),
      tab,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: kp + Offset(0, capR - 2), width: tw, height: th),
        const Radius.circular(1),
      ),
      tab,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: kp + Offset(-capR + 2, 0), width: th, height: tw),
        const Radius.circular(1),
      ),
      tab,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: kp + Offset(capR - 2, 0), width: th, height: tw),
        const Radius.circular(1),
      ),
      tab,
    );

    canvas.drawCircle(
      kp,
      2.2,
      Paint()..color = TxPalette.amber.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _GimbalPainter old) =>
      old.knob != knob || old.highlightBottom != highlightBottom;
}
