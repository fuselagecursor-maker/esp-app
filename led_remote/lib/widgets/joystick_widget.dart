import 'package:flutter/material.dart';

/// Virtual gimbal. [zoneMode] + [transmitterStyle] for RC handset sticks.
class JoystickWidget extends StatefulWidget {
  const JoystickWidget({
    super.key,
    this.label,
    this.subtitle,
    this.onChanged,
    this.onReleased,
    this.size = 148,
    this.zoneMode = false,
    this.zoneAnchor = Alignment.bottomCenter,
    this.showValues = true,
    this.transmitterStyle = false,
    this.showCenterDetent = false,
  });

  final String? label;
  final String? subtitle;
  final void Function(double x, double y)? onChanged;
  final VoidCallback? onReleased;
  final double size;
  final bool zoneMode;
  final Alignment zoneAnchor;
  final bool showValues;
  final bool transmitterStyle;
  /// Draw center tick (e.g. throttle idle at 30%).
  final bool showCenterDetent;

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  Offset _knob = Offset.zero;
  bool _active = false;

  void _applyKnob(double nx, double ny, {required bool active}) {
    setState(() {
      _knob = Offset(nx, ny);
      _active = active;
    });
    widget.onChanged?.call(nx, ny);
  }

  void _updateFromLocal(Offset local, Offset baseCenter, double radius) {
    var delta = local - baseCenter;
    final len = delta.distance;
    if (len > radius) {
      delta = Offset.fromDirection(delta.direction, radius);
    }
    final nx = (delta.dx / radius).clamp(-1.0, 1.0);
    final ny = (-delta.dy / radius).clamp(-1.0, 1.0);
    _applyKnob(nx, ny, active: true);
  }

  /// Spring gimbal back to centre and notify parent (throttle → idle 30%).
  void _reset() {
    setState(() {
      _knob = Offset.zero;
      _active = false;
    });
    widget.onChanged?.call(0, 0);
    widget.onReleased?.call();
  }

  ({Offset center, double radius}) _geometry(Size size) {
    final pad = widget.transmitterStyle ? 28.0 : 20.0;
    final r = widget.zoneMode
        ? (size.shortestSide * 0.38).clamp(68.0, 150.0)
        : widget.size / 2;

    if (!widget.zoneMode) {
      return (center: Offset(size.width / 2, size.height / 2), radius: r);
    }

    final ax = widget.zoneAnchor.x;
    final ay = widget.zoneAnchor.y;
    final cx = ax < 0
        ? pad + r
        : ax > 0
            ? size.width - pad - r
            : size.width / 2;
    final cy = ay < 0
        ? size.height - pad - r
        : ay > 0
            ? pad + r
            : size.height / 2;
    return (center: Offset(cx, cy), radius: r);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tx = widget.transmitterStyle || widget.zoneMode;

    if (widget.zoneMode) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final geo = _geometry(size);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (e) => _updateFromLocal(e.localPosition, geo.center, geo.radius),
            onPanUpdate: (e) => _updateFromLocal(e.localPosition, geo.center, geo.radius),
            onPanEnd: (_) => _reset(),
            onPanCancel: _reset,
            child: CustomPaint(
              painter: _JoystickPainter(
                knob: _knob,
                active: _active,
                baseCenter: geo.center,
                radius: geo.radius,
                transmitterStyle: tx,
                showCenterDetent: widget.showCenterDetent,
                color: cs.primary,
                track: cs.surfaceContainerHighest,
                outline: cs.outlineVariant,
              ),
              size: size,
            ),
          );
        },
      );
    }

    final d = widget.size;
    final geo = (center: Offset(d / 2, d / 2), radius: d / 2);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Text(
            widget.label!,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            widget.subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: d,
          height: d,
          child: GestureDetector(
            onPanDown: (e) => _updateFromLocal(e.localPosition, geo.center, geo.radius),
            onPanUpdate: (e) => _updateFromLocal(e.localPosition, geo.center, geo.radius),
            onPanEnd: (_) => _reset(),
            onPanCancel: _reset,
            child: CustomPaint(
              painter: _JoystickPainter(
                knob: _knob,
                active: _active,
                baseCenter: geo.center,
                radius: geo.radius,
                transmitterStyle: tx,
                showCenterDetent: widget.showCenterDetent,
                color: cs.primary,
                track: cs.surfaceContainerHighest,
                outline: cs.outlineVariant,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        if (widget.showValues) ...[
          const SizedBox(height: 6),
          Text(
            'X ${_pct(_knob.dx)}  Y ${_pct(_knob.dy)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }

  String _pct(double v) => (v * 100).round().toString().padLeft(4);
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({
    required this.knob,
    required this.active,
    required this.baseCenter,
    required this.radius,
    required this.transmitterStyle,
    required this.showCenterDetent,
    required this.color,
    required this.track,
    required this.outline,
  });

  final Offset knob;
  final bool active;
  final Offset baseCenter;
  final double radius;
  final bool transmitterStyle;
  final bool showCenterDetent;
  final Color color;
  final Color track;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final knobR = transmitterStyle ? radius * 0.24 : 22.0;
    final travel = radius - knobR - 6;

    if (transmitterStyle) {
      final housing = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: baseCenter,
          width: radius * 2.15,
          height: radius * 2.15,
        ),
        Radius.circular(radius * 0.2),
      );
      canvas.drawRRect(
        housing,
        Paint()..color = const Color(0xFF1C2126),
      );
      canvas.drawRRect(
        housing,
        Paint()
          ..color = const Color(0xFF4A555E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      canvas.drawCircle(
        baseCenter,
        radius,
        Paint()..color = const Color(0xFF252A2F),
      );
      canvas.drawCircle(
        baseCenter,
        radius,
        Paint()
          ..color = const Color(0xFF3D484F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      final slot = Paint()
        ..color = const Color(0xFF15191D)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(baseCenter.dx, baseCenter.dy - radius + 10),
        Offset(baseCenter.dx, baseCenter.dy + radius - 10),
        slot,
      );
      canvas.drawLine(
        Offset(baseCenter.dx - radius + 10, baseCenter.dy),
        Offset(baseCenter.dx + radius - 10, baseCenter.dy),
        slot,
      );

      if (showCenterDetent) {
        canvas.drawCircle(
          baseCenter,
          5,
          Paint()..color = const Color(0xFFE8A317).withValues(alpha: 0.9),
        );
        canvas.drawCircle(
          baseCenter,
          7,
          Paint()
            ..color = const Color(0xFFE8A317).withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    } else {
      canvas.drawCircle(
        baseCenter,
        radius,
        Paint()
          ..color = track
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        baseCenter,
        radius,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    final knobPos = Offset(
      baseCenter.dx + knob.dx * travel,
      baseCenter.dy - knob.dy * travel,
    );

    if (knob != Offset.zero && !transmitterStyle) {
      canvas.drawLine(
        baseCenter,
        knobPos,
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    if (transmitterStyle) {
      canvas.drawCircle(
        knobPos,
        knobR + 4,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }

    canvas.drawCircle(
      knobPos,
      knobR,
      Paint()
        ..color = transmitterStyle
            ? (active ? const Color(0xFFF0F2F4) : const Color(0xFFB0BCC4))
            : (active ? color : color.withValues(alpha: 0.65))
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      knobPos,
      knobR,
      Paint()
        ..color = transmitterStyle
            ? (active ? const Color(0xFFE8A317) : const Color(0xFF5C6A72))
            : color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = transmitterStyle ? 2.5 : 2,
    );

    if (transmitterStyle) {
      canvas.drawCircle(
        knobPos + const Offset(-2, -2),
        knobR * 0.3,
        Paint()..color = Colors.white.withValues(alpha: active ? 0.4 : 0.15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter old) {
    return old.knob != knob ||
        old.active != active ||
        old.baseCenter != baseCenter ||
        old.radius != radius ||
        old.showCenterDetent != showCenterDetent;
  }
}
