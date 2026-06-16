import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tx_palette.dart';

/// Anodized panel with 3px inset border and seven rivets.
class TransmitterFaceplate extends StatelessWidget {
  const TransmitterFaceplate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: _FaceplatePainter()),
        Padding(
          padding: const EdgeInsets.all(3),
          child: child,
        ),
      ],
    );
  }
}

class _FaceplatePainter extends CustomPainter {
  const _FaceplatePainter();

  static const _inset = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = TxPalette.panel,
    );

    final inner = Rect.fromLTWH(
      _inset,
      _inset,
      size.width - _inset * 2,
      size.height - _inset * 2,
    );
    canvas.drawRect(inner, Paint()..color = TxPalette.panelDeep);

    final border = Paint()
      ..color = TxPalette.engraved
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(inner, border);
    canvas.drawRect(
      inner.deflate(1),
      border..color = TxPalette.engraved.withValues(alpha: 0.55),
    );

    final rivets = <Offset>[
      Offset(inner.left + 10, inner.top + 10),
      Offset(inner.center.dx, inner.top + 10),
      Offset(inner.right - 10, inner.top + 10),
      Offset(inner.left + 10, inner.center.dy),
      Offset(inner.left + 10, inner.bottom - 10),
      Offset(inner.center.dx, inner.bottom - 10),
      Offset(inner.right - 10, inner.bottom - 10),
    ];
    for (final p in rivets) {
      _drawRivet(canvas, p);
    }
  }

  void _drawRivet(Canvas canvas, Offset c) {
    const r = 5.0;
    canvas.drawCircle(c, r, Paint()..color = TxPalette.rivetBody);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = TxPalette.engraved
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.drawCircle(c + const Offset(-0.8, -0.8), 1.6, Paint()..color = TxPalette.rivetHi);
    final slot = Paint()
      ..color = TxPalette.engraved
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      c + Offset(-r * 0.55, 0),
      c + Offset(r * 0.55, 0),
      slot,
    );
    canvas.drawLine(
      c + Offset.fromDirection(math.pi / 2, r * 0.35),
      c + Offset.fromDirection(-math.pi / 2, r * 0.35),
      slot..strokeWidth = 0.6,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
