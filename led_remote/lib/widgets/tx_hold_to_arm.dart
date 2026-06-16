import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tx_palette.dart';

/// Optional colors (e.g. FC Tune light mode). Defaults to [TxPalette].
class TxArmSwitchColors {
  const TxArmSwitchColors({
    required this.track,
    required this.border,
    required this.guard,
    required this.lever,
    required this.leverBusy,
    required this.amber,
    required this.labelMuted,
    required this.armLed,
  });

  final Color track;
  final Color border;
  final Color guard;
  final Color lever;
  final Color leverBusy;
  final Color amber;
  final Color labelMuted;
  final Color armLed;
}

/// Transmitter ARM switch: tap to disarm; hold lever up to arm.
class TxHoldToArmSwitch extends StatefulWidget {
  const TxHoldToArmSwitch({
    super.key,
    required this.armed,
    required this.busy,
    required this.onDisarm,
    required this.onArmHoldComplete,
    this.holdDuration = const Duration(milliseconds: 1200),
    this.colors,
  });

  final bool armed;
  final bool busy;
  final VoidCallback onDisarm;
  final Future<void> Function() onArmHoldComplete;
  final Duration holdDuration;
  final TxArmSwitchColors? colors;

  @override
  State<TxHoldToArmSwitch> createState() => _TxHoldToArmSwitchState();
}

class _TxHoldToArmSwitchState extends State<TxHoldToArmSwitch> {
  Timer? _holdTimer;
  double _holdProgress = 0;
  bool _holding = false;

  @override
  void dispose() {
    _cancelHold();
    super.dispose();
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_holding || _holdProgress > 0) {
      setState(() {
        _holding = false;
        _holdProgress = 0;
      });
    }
  }

  void _startHold() {
    if (widget.armed || widget.busy) return;
    _cancelHold();
    setState(() {
      _holding = true;
      _holdProgress = 0;
    });
    final started = DateTime.now();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 40), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(started);
      final p = (elapsed.inMilliseconds / widget.holdDuration.inMilliseconds)
          .clamp(0.0, 1.0);
      setState(() => _holdProgress = p);
      if (p >= 1.0) {
        t.cancel();
        _holdTimer = null;
        setState(() {
          _holding = false;
          _holdProgress = 0;
        });
        HapticFeedback.heavyImpact();
        await widget.onArmHoldComplete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.armed || widget.busy
          ? null
          : (_) => _startHold(),
      onPointerUp: widget.armed || widget.busy ? null : (_) => _cancelHold(),
      onPointerCancel: widget.armed || widget.busy ? null : (_) => _cancelHold(),
      child: GestureDetector(
        onTap: widget.busy
            ? null
            : widget.armed
                ? widget.onDisarm
                : null,
        child: CustomPaint(
          size: const Size(52, 72),
          painter: _ArmPainter(
            armed: widget.armed,
            busy: widget.busy,
            holding: _holding,
            holdProgress: _holdProgress,
            colors: widget.colors,
          ),
        ),
      ),
    );
  }
}

class _ArmPainter extends CustomPainter {
  _ArmPainter({
    required this.armed,
    required this.busy,
    required this.holding,
    required this.holdProgress,
    this.colors,
  });

  final bool armed;
  final bool busy;
  final bool holding;
  final double holdProgress;
  final TxArmSwitchColors? colors;

  TxArmSwitchColors get _c => colors ?? _defaultColors;

  static final _defaultColors = TxArmSwitchColors(
    track: TxPalette.track,
    border: TxPalette.engraved,
    guard: const Color(0xFF35393D),
    lever: const Color(0xFF2A2E32),
    leverBusy: const Color(0xFF3A3E42),
    amber: TxPalette.amber,
    labelMuted: TxPalette.labelMuted,
    armLed: TxPalette.armLed,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final c = _c;
    final housing = RRect.fromRectAndRadius(
      Rect.fromLTWH(6, 14, 40, 54),
      const Radius.circular(3),
    );
    canvas.drawRRect(housing, Paint()..color = c.track);
    canvas.drawRRect(
      housing,
      Paint()
        ..color = c.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final guard = RRect.fromRectAndRadius(
      Rect.fromLTWH(10, 4, 32, 14),
      const Radius.circular(2),
    );
    canvas.drawRRect(guard, Paint()..color = c.guard);
    final tp = TextPainter(
      text: TextSpan(
        text: holding ? 'HOLD' : 'SAFE',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 7,
          letterSpacing: 1,
          color: holding ? c.amber : c.labelMuted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(holding ? 14 : 16, 7));

    final leverTop = armed ? 22.0 : (38.0 - holdProgress * 16);
    final lever = RRect.fromRectAndRadius(
      Rect.fromLTWH(14, leverTop, 24, 22),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      lever,
      Paint()..color = busy ? c.leverBusy : c.lever,
    );

    if (holding && holdProgress > 0) {
      final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(12, 58, 28 * holdProgress, 3),
        const Radius.circular(1),
      );
      canvas.drawRRect(bar, Paint()..color = c.amber);
    }

    if (armed) {
      canvas.drawCircle(
        const Offset(26, 33),
        3.5,
        Paint()..color = c.armLed,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArmPainter old) =>
      old.armed != armed ||
      old.busy != busy ||
      old.holding != holding ||
      old.holdProgress != holdProgress ||
      old.colors != colors;
}

/// Compact hold-to-ARM chip for Manual / Home headers.
class TxHoldArmChip extends StatefulWidget {
  const TxHoldArmChip({
    super.key,
    required this.armed,
    required this.busy,
    required this.onDisarm,
    required this.onArmHoldComplete,
    this.holdDuration = const Duration(milliseconds: 1200),
  });

  final bool armed;
  final bool busy;
  final VoidCallback onDisarm;
  final Future<void> Function() onArmHoldComplete;
  final Duration holdDuration;

  @override
  State<TxHoldArmChip> createState() => _TxHoldArmChipState();
}

class _TxHoldArmChipState extends State<TxHoldArmChip> {
  Timer? _timer;
  double _progress = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    if (_progress > 0 && mounted) setState(() => _progress = 0);
  }

  void _startHold() {
    if (widget.armed || widget.busy) return;
    _cancel();
    final started = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 40), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      final p = (DateTime.now().difference(started).inMilliseconds /
              widget.holdDuration.inMilliseconds)
          .clamp(0.0, 1.0);
      setState(() => _progress = p);
      if (p >= 1.0) {
        t.cancel();
        _timer = null;
        if (mounted) setState(() => _progress = 0);
        HapticFeedback.heavyImpact();
        await widget.onArmHoldComplete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.busy
        ? '...'
        : widget.armed
            ? 'DISARM'
            : (_progress > 0 ? 'HOLD…' : 'HOLD ARM');

    final child = Material(
      color: widget.armed
          ? TxPalette.amber.withValues(alpha: 0.22)
          : TxPalette.panelDeep,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: widget.busy
            ? null
            : widget.armed
                ? widget.onDisarm
                : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TxPalette.labelStyle.copyWith(fontSize: 8)),
              if (_progress > 0 && !widget.armed)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 2,
                    backgroundColor: TxPalette.track,
                    color: TxPalette.amber,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.armed || widget.busy) return child;

    return Listener(
      onPointerDown: (_) => _startHold(),
      onPointerUp: (_) => _cancel(),
      onPointerCancel: (_) => _cancel(),
      child: child,
    );
  }
}
