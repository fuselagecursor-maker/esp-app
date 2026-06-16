import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen emergency stop — one tap, no confirmation, no busy gate.
class KillPage extends StatelessWidget {
  const KillPage({
    super.key,
    required this.useEsp,
    required this.onKill,
    this.lastKillAt,
  });

  final bool useEsp;
  final VoidCallback onKill;
  final DateTime? lastKillAt;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0A0A0A),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'EMERGENCY STOP',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red.shade300,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                useEsp
                    ? 'Instant: rc off · throttle 0 · disarm (parallel, no STM32 wait)'
                    : 'Enable Live ESP on Home — kill still clears app armed state',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const Spacer(flex: 2),
              _KillTarget(onKill: onKill),
              const Spacer(flex: 3),
              if (lastKillAt != null)
                Text(
                  'Last kill ${ _formatTime(lastKillAt!)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'No confirmation · tap anywhere on the red button',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _KillTarget extends StatefulWidget {
  const _KillTarget({required this.onKill});

  final VoidCallback onKill;

  @override
  State<_KillTarget> createState() => _KillTargetState();
}

class _KillTargetState extends State<_KillTarget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat(reverse: true);

  bool _pressed = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _fire() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    widget.onKill();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.35 + _pulse.value * 0.25;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            setState(() => _pressed = true);
            _fire();
          },
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 80),
            child: Container(
              height: MediaQuery.sizeOf(context).height * 0.42,
              constraints: const BoxConstraints(minHeight: 200, maxHeight: 360),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 1.1,
                  colors: [
                    Color.lerp(const Color(0xFFEF4444), const Color(0xFFB91C1C), glow)!,
                    const Color(0xFF7F1D1D),
                    const Color(0xFF450A0A),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withValues(alpha: glow * 0.55),
                    blurRadius: 32 + glow * 24,
                    spreadRadius: 2,
                  ),
                ],
                border: Border.all(
                  color: Color.lerp(const Color(0xFFFECACA), const Color(0xFFFCA5A5), glow)!,
                  width: 3,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.emergency_rounded,
                    size: 72,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'KILL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 12,
                      height: 1,
                      shadows: [
                        Shadow(
                          color: Color(0x66000000),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'STOP MOTORS NOW',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
