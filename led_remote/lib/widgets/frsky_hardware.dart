import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/frsky_palette.dart';

/// Olive-green faceplate with dark outer bezel.
class FrSkyFaceplate extends StatelessWidget {
  const FrSkyFaceplate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: _FaceplatePainter()),
        child,
      ],
    );
  }
}

class _FaceplatePainter extends CustomPainter {
  const _FaceplatePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.zero,
    );
    canvas.drawRRect(outer, Paint()..color = FrSkyPalette.bodyCharcoal);
    const insetPx = 2.0;
    final inset = RRect.fromRectAndRadius(
      Rect.fromLTWH(insetPx, insetPx, size.width - insetPx * 2, size.height - insetPx * 2),
      Radius.zero,
    );
    canvas.drawRRect(
      inset,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            FrSkyPalette.faceplateHi,
            FrSkyPalette.faceplate,
            FrSkyPalette.faceplateShadow,
          ],
        ).createShader(inset.outerRect),
    );
    canvas.drawRRect(
      inset,
      Paint()
        ..color = FrSkyPalette.faceplateShadow.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 2-position toggle (SA / SD style).
class FrSkyToggle extends StatelessWidget {
  const FrSkyToggle({
    super.key,
    required this.label,
    required this.onPressed,
    this.engaged = false,
    this.accent = FrSkyPalette.silver,
  });

  final String label;
  final VoidCallback onPressed;
  final bool engaged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2E32),
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: engaged ? 6 : 24,
                  child: Container(
                    width: 22,
                    height: 18,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: engaged
                            ? [accent, accent.withValues(alpha: 0.7)]
                            : [FrSkyPalette.silverHi, FrSkyPalette.silver],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFF606870)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: FrSkyPalette.label,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bronze rotary knob (decorative / tap).
class FrSkyKnob extends StatelessWidget {
  const FrSkyKnob({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [FrSkyPalette.bronzeHi, FrSkyPalette.bronze, Color(0xFF6B5A3A)],
              ),
              border: Border.all(color: const Color(0xFF4A4030), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CustomPaint(painter: _KnobTicksPainter()),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: FrSkyPalette.labelDim),
          ),
        ],
      ),
    );
  }
}

class _KnobTicksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()
      ..color = const Color(0xFF3D3528)
      ..strokeWidth = 1.5;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawLine(
        c + Offset.fromDirection(a, 10),
        c + Offset.fromDirection(a, 14),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Vertical trim slider (T1–T6 style).
class FrSkyTrim extends StatelessWidget {
  const FrSkyTrim({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D20),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFF404850)),
          ),
          child: Align(
            alignment: Alignment.center,
            child: Container(
              width: 18,
              height: 10,
              decoration: BoxDecoration(
                color: FrSkyPalette.silver,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 8, color: FrSkyPalette.labelDim),
        ),
      ],
    );
  }
}

/// Centre arm/disarm safety lever — up + glow = armed, down = disarmed.
class FrSkyArmLever extends StatelessWidget {
  const FrSkyArmLever({
    super.key,
    required this.armed,
    required this.onToggle,
    this.busy = false,
  });

  final bool armed;
  final VoidCallback onToggle;
  final bool busy;

  static const _slotW = 30.0;
  static const _slotH = 52.0;
  static const _handleH = 14.0;

  @override
  Widget build(BuildContext context) {
    final glow = armed
        ? [
            BoxShadow(
              color: FrSkyPalette.armGreen.withValues(alpha: 0.75),
              blurRadius: 14,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: FrSkyPalette.armGreen.withValues(alpha: 0.35),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ]
        : <BoxShadow>[];

    return Center(
      child: GestureDetector(
        onTap: busy ? null : onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: _slotW + 8,
          height: _slotH + 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            boxShadow: glow,
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: _slotW,
              height: _slotH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: armed ? FrSkyPalette.armGreen : FrSkyPalette.bronze,
                  width: 2,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: armed
                      ? [
                          const Color(0xFF2A3D2A),
                          const Color(0xFF1A1D20),
                        ]
                      : [
                          const Color(0xFF2A2E32),
                          const Color(0xFF1A1D20),
                        ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (armed)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: RadialGradient(
                            center: const Alignment(0, -0.5),
                            radius: 1.1,
                            colors: [
                              FrSkyPalette.armGreen.withValues(alpha: 0.45),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment:
                        armed ? Alignment.topCenter : Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: _LeverHandle(
                        armed: armed,
                        busy: busy,
                      ),
                    ),
                  ),
                  if (busy)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x44000000),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LeverHandle extends StatelessWidget {
  const _LeverHandle({required this.armed, required this.busy});

  final bool armed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 22,
      height: FrSkyArmLever._handleH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: armed
              ? [
                  FrSkyPalette.armGreen,
                  const Color(0xFF3D8B3D),
                ]
              : busy
                  ? [
                      const Color(0xFF606870),
                      const Color(0xFF404850),
                    ]
                  : [
                      FrSkyPalette.silverHi,
                      FrSkyPalette.silver,
                    ],
        ),
        border: Border.all(
          color: armed
              ? const Color(0xFF7FD67F)
              : const Color(0xFF606870),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
          if (armed)
            BoxShadow(
              color: FrSkyPalette.armGreen.withValues(alpha: 0.9),
              blurRadius: 8,
              spreadRadius: 1,
            ),
        ],
      ),
      child: CustomPaint(
        painter: _LeverGripPainter(),
      ),
    );
  }
}

class _LeverGripPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF404850).withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final cy = size.height / 2;
    for (var i = -1; i <= 1; i++) {
      canvas.drawLine(
        Offset(5, cy + i * 3),
        Offset(size.width - 5, cy + i * 3),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Compact throttle readout (center sticks via CTR).
class FrSkyLcdPanel extends StatelessWidget {
  const FrSkyLcdPanel({
    super.key,
    required this.throttle,
    this.onCenter,
  });

  final int throttle;
  final VoidCallback? onCenter;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: FrSkyPalette.screenBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FrSkyPalette.bronze, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Text(
            'THR $throttle%',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1,
              fontWeight: FontWeight.w700,
              color: throttle == 30
                  ? FrSkyPalette.screenLine
                  : FrSkyPalette.bronzeHi,
            ),
          ),
          const Spacer(),
          if (onCenter != null)
            GestureDetector(
              onTap: onCenter,
              child: const Text(
                'CTR',
                style: TextStyle(
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: FrSkyPalette.bronzeHi,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Left nav cluster MDL / SYS / TELE / RTN.
class FrSkyNavCluster extends StatelessWidget {
  const FrSkyNavCluster({super.key, this.onCenter});

  final VoidCallback? onCenter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF2A2E32),
            ),
          ),
          Positioned(top: 4, child: _navLabel('MDL')),
          Positioned(bottom: 4, child: _navLabel('RTN')),
          Positioned(left: 2, child: _navLabel('SYS')),
          Positioned(right: 2, child: _navLabel('TELE')),
          GestureDetector(
            onTap: onCenter,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFF4A5058), Color(0xFF2A2E32)],
                ),
                border: Border.all(color: FrSkyPalette.bronze),
              ),
              child: const Center(
                child: Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: FrSkyPalette.label,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navLabel(String t) => Text(
        t,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: FrSkyPalette.labelDim,
        ),
      );
}

/// Bronze scroll wheel (decorative).
class FrSkyScrollWheel extends StatelessWidget {
  const FrSkyScrollWheel({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [FrSkyPalette.bronzeHi, FrSkyPalette.bronze, Color(0xFF5A4A32)],
            ),
            border: Border.all(color: const Color(0xFF3D3528), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: CustomPaint(painter: _ScrollWheelPainter()),
        ),
      ],
    );
  }
}

class _ScrollWheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()
      ..color = const Color(0xFF4A4030)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < 24; i++) {
      final a = i * math.pi / 12;
      canvas.drawLine(
        c + Offset.fromDirection(a, 16),
        c + Offset.fromDirection(a, 22),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
