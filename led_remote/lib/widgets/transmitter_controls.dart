import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tx_palette.dart';

/// SA/SB/SC/SD — tall flip switch, up = on (amber), down = dark.
class TxFlipSwitch extends StatefulWidget {
  const TxFlipSwitch({
    super.key,
    required this.label,
    this.onChanged,
    this.initialOn = false,
  });

  final String label;
  final ValueChanged<bool>? onChanged;
  final bool initialOn;

  @override
  State<TxFlipSwitch> createState() => _TxFlipSwitchState();
}

class _TxFlipSwitchState extends State<TxFlipSwitch> {
  late bool _on = widget.initialOn;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _on = !_on);
        widget.onChanged?.call(_on);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(28, 48),
            painter: _FlipPainter(on: _on),
          ),
          const SizedBox(height: 3),
          Text(widget.label, style: TxPalette.labelStyle),
        ],
      ),
    );
  }
}

class _FlipPainter extends CustomPainter {
  _FlipPainter({required this.on});

  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 0, size.width - 4, size.height - 2),
      const Radius.circular(2),
    );
    canvas.drawRRect(body, Paint()..color = TxPalette.track);
    canvas.drawRRect(
      body,
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final lever = RRect.fromRectAndRadius(
      Rect.fromLTWH(5, on ? 5 : 24, size.width - 10, 16),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      lever,
      Paint()..color = on ? TxPalette.amber : const Color(0xFF2E3236),
    );
    canvas.drawRRect(
      lever,
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant _FlipPainter old) => old.on != on;
}

/// Analog gauge (dashed scale + amber needle). Size fixed at 40×40.
class TxAnalogGauge extends StatelessWidget {
  const TxAnalogGauge({
    super.key,
    required this.label,
    required this.value,
    this.centered = false,
    this.minAngleDeg = -120,
    this.maxAngleDeg = 120,
  });

  final String label;

  /// 0…1 for throttle-style; −1…1 when [centered] is true.
  final double value;
  final bool centered;
  final double minAngleDeg;
  final double maxAngleDeg;

  double get _angleDeg {
    if (centered) {
      return value.clamp(-1.0, 1.0) * maxAngleDeg;
    }
    final t = value.clamp(0.0, 1.0);
    return minAngleDeg + t * (maxAngleDeg - minAngleDeg);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(40, 40),
          painter: _KnobPainter(angleDeg: _angleDeg),
        ),
        const SizedBox(height: 2),
        Text(label, style: TxPalette.labelStyle),
      ],
    );
  }
}

class _KnobPainter extends CustomPainter {
  _KnobPainter({required this.angleDeg});

  final double angleDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;
    canvas.drawCircle(c, r, Paint()..color = TxPalette.track);
    final dash = Paint()
      ..color = TxPalette.labelMuted.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = 0; i < 24; i++) {
      final a = i * math.pi / 12;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 2),
        a,
        0.08,
        false,
        dash,
      );
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final rad = (angleDeg - 90) * math.pi / 180;
    canvas.drawLine(
      c,
      c + Offset(math.cos(rad), math.sin(rad)) * (r - 6),
      Paint()
        ..color = TxPalette.amber
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _KnobPainter old) => old.angleDeg != angleDeg;
}

/// T1–T4 vertical trim slider.
class TxVerticalSlider extends StatelessWidget {
  const TxVerticalSlider({
    super.key,
    required this.label,
    this.value = 0.5,
  });

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(16, 52),
          painter: _SliderPainter(value: value.clamp(0.0, 1.0)),
        ),
        const SizedBox(height: 2),
        Text(label, style: TxPalette.labelStyle),
      ],
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, 2, 8, size.height - 4),
      const Radius.circular(2),
    );
    canvas.drawRRect(track, Paint()..color = TxPalette.track);
    for (var i = 1; i <= 4; i++) {
      final y = 2 + (size.height - 4) * (i / 5);
      canvas.drawLine(
        Offset(2, y),
        Offset(size.width - 2, y),
        Paint()
          ..color = TxPalette.engraved
          ..strokeWidth = 0.6,
      );
    }
    final fillH = (size.height - 4) * value;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          5,
          size.height - 2 - fillH,
          11,
          size.height - 2,
        ),
        const Radius.circular(1),
      ),
      Paint()..color = TxPalette.amber.withValues(alpha: 0.75),
    );
    final thumbY = size.height - 2 - fillH;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(8, thumbY), width: 12, height: 6),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFF4A4E54),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(8, thumbY), width: 12, height: 6),
        const Radius.circular(1),
      ),
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) => old.value != value;
}

/// ARM in housing with SAFE guard; green LED when armed (only glow).
class TxArmSwitch extends StatelessWidget {
  const TxArmSwitch({
    super.key,
    required this.armed,
    required this.busy,
    required this.onToggle,
  });

  final bool armed;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onToggle,
      child: CustomPaint(
        size: const Size(52, 72),
        painter: _ArmPainter(armed: armed, busy: busy),
      ),
    );
  }
}

class _ArmPainter extends CustomPainter {
  _ArmPainter({required this.armed, required this.busy});

  final bool armed;
  final bool busy;

  @override
  void paint(Canvas canvas, Size size) {
    final housing = RRect.fromRectAndRadius(
      Rect.fromLTWH(6, 14, 40, 54),
      const Radius.circular(3),
    );
    canvas.drawRRect(housing, Paint()..color = TxPalette.track);
    canvas.drawRRect(
      housing,
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final guard = RRect.fromRectAndRadius(
      Rect.fromLTWH(10, 4, 32, 14),
      const Radius.circular(2),
    );
    canvas.drawRRect(guard, Paint()..color = const Color(0xFF35393D));
    canvas.drawRRect(
      guard,
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'SAFE',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 7,
          letterSpacing: 1,
          color: TxPalette.labelMuted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(16, 7));

    final leverTop = armed ? 22.0 : 38.0;
    final lever = RRect.fromRectAndRadius(
      Rect.fromLTWH(14, leverTop, 24, 22),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      lever,
      Paint()..color = busy ? const Color(0xFF3A3E42) : const Color(0xFF2A2E32),
    );
    canvas.drawRRect(
      lever,
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    if (armed) {
      canvas.drawCircle(
        const Offset(26, 33),
        3.5,
        Paint()..color = TxPalette.armLed,
      );
      canvas.drawCircle(
        const Offset(25.2, 32.2),
        1.2,
        Paint()..color = const Color(0xFF90FFA0),
      );
    } else {
      canvas.drawCircle(
        const Offset(26, 47),
        3,
        Paint()..color = TxPalette.ledOff,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArmPainter old) =>
      old.armed != armed || old.busy != busy;
}

/// T5/T6 micro two-position toggle.
class TxMicroToggle extends StatefulWidget {
  const TxMicroToggle({super.key, required this.label});

  final String label;

  @override
  State<TxMicroToggle> createState() => _TxMicroToggleState();
}

class _TxMicroToggleState extends State<TxMicroToggle> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _on = !_on),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(22, 18),
            painter: _MicroPainter(on: _on),
          ),
          const SizedBox(height: 2),
          Text(widget.label, style: TxPalette.labelStyle),
        ],
      ),
    );
  }
}

class _MicroPainter extends CustomPainter {
  _MicroPainter({required this.on});

  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 4, size.width, 12),
        const Radius.circular(2),
      ),
      Paint()..color = TxPalette.track,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(on ? 11 : 1, 2, 10, 14),
        const Radius.circular(2),
      ),
      Paint()..color = on ? TxPalette.amber : const Color(0xFF3A3E42),
    );
  }

  @override
  bool shouldRepaint(covariant _MicroPainter old) => old.on != on;
}

/// Full-width recessed status strip.
class TxStatusBar extends StatefulWidget {
  const TxStatusBar({
    super.key,
    required this.throttlePct,
    required this.linkActive,
    this.modelId = 'X10-RC',
  });

  final int throttlePct;
  final bool linkActive;
  final String modelId;

  @override
  State<TxStatusBar> createState() => _TxStatusBarState();
}

class _TxStatusBarState extends State<TxStatusBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _linkPulse;
  double _thrFrom = 0;

  @override
  void initState() {
    super.initState();
    _thrFrom = widget.throttlePct.toDouble();
    _linkPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _syncLinkPulse();
  }

  @override
  void didUpdateWidget(covariant TxStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.throttlePct != widget.throttlePct) {
      _thrFrom = oldWidget.throttlePct.toDouble();
    }
    _syncLinkPulse();
  }

  void _syncLinkPulse() {
    if (widget.linkActive) {
      if (!_linkPulse.isAnimating) _linkPulse.repeat(reverse: true);
    } else {
      _linkPulse.stop();
      _linkPulse.value = 0;
    }
  }

  @override
  void dispose() {
    _linkPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(widget.throttlePct),
      tween: Tween<double>(
        begin: _thrFrom,
        end: widget.throttlePct.toDouble(),
      ),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, thr, _) {
        return AnimatedBuilder(
          animation: _linkPulse,
          builder: (context, _) {
            return CustomPaint(
              painter: _StatusPainter(
                throttlePct: thr.round(),
                linkActive: widget.linkActive,
                linkPulse: _linkPulse.value,
                modelId: widget.modelId,
              ),
              child: const SizedBox(height: 40, width: double.infinity),
            );
          },
        );
      },
    );
  }
}

class _StatusPainter extends CustomPainter {
  _StatusPainter({
    required this.throttlePct,
    required this.linkActive,
    required this.linkPulse,
    required this.modelId,
  });

  final int throttlePct;
  final bool linkActive;
  final double linkPulse;
  final String modelId;

  @override
  void paint(Canvas canvas, Size size) {
    final strip = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 2, size.width, size.height - 4),
      const Radius.circular(2),
    );
    canvas.drawRRect(strip, Paint()..color = TxPalette.statusBg);
    canvas.drawRRect(
      strip,
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    void led(Offset c, Color color) {
      canvas.drawCircle(c, 3, Paint()..color = color);
      canvas.drawCircle(
        c + const Offset(-0.5, -0.5),
        1.2,
        Paint()..color = Colors.white.withValues(alpha: 0.15),
      );
    }

    led(const Offset(14, 20), TxPalette.amber);
    final linkColor = linkActive
        ? Color.lerp(
            TxPalette.armLed.withValues(alpha: 0.55),
            TxPalette.armLed,
            0.55 + linkPulse * 0.45,
          )!
        : TxPalette.ledOff;
    led(const Offset(28, 20), linkColor);
    led(const Offset(42, 20), TxPalette.ledOff);

    _label(canvas, 'THR', 56, 14);
    final trackL = 78.0;
    final trackW = size.width - 200;
    final trackR = RRect.fromRectAndRadius(
      Rect.fromLTWH(trackL, 16, trackW, 8),
      const Radius.circular(1),
    );
    canvas.drawRRect(trackR, Paint()..color = TxPalette.track);
    final fillW = trackW * (throttlePct / 100);
    if (fillW > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(trackL, 16, trackL + fillW, 24),
          const Radius.circular(1),
        ),
        Paint()..color = TxPalette.amber.withValues(alpha: 0.85),
      );
    }
    _label(canvas, '$throttlePct%', trackL + trackW + 8, 14);

    _label(canvas, 'LINK', 28, 28);
    _label(canvas, linkActive ? 'ON' : 'OFF', 42, 28);

    final badge = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - 72, 10, 64, 20),
      const Radius.circular(2),
    );
    canvas.drawRRect(badge, Paint()..color = TxPalette.track);
    canvas.drawRRect(
      badge,
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    final idTp = TextPainter(
      text: TextSpan(
        text: modelId,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 9,
          letterSpacing: 2,
          color: TxPalette.amber,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    idTp.paint(canvas, Offset(size.width - 68, 14));
  }

  void _label(Canvas canvas, String t, double x, double y) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TxPalette.labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _StatusPainter old) =>
      old.throttlePct != throttlePct ||
      old.linkActive != linkActive ||
      old.linkPulse != linkPulse ||
      old.modelId != modelId;
}
