import 'package:flutter/material.dart';

/// Shared motion primitives — colors/themes unchanged; motion only.
abstract final class AppMotion {
  static const tabMs = Duration(milliseconds: 240);
  static const fastMs = Duration(milliseconds: 160);
  static const mediumMs = Duration(milliseconds: 280);
  static const staggerStep = Duration(milliseconds: 55);
}

/// Fade + slight slide when switching main tabs.
class AppTabTransition extends StatelessWidget {
  const AppTabTransition({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.tabMs,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [
          ...previous,
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.018, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Staggered entrance for Home sections and similar lists.
class StaggeredFadeIn extends StatefulWidget {
  const StaggeredFadeIn({
    super.key,
    required this.index,
    required this.child,
    this.delay = AppMotion.staggerStep,
  });

  final int index;
  final Widget child;
  final Duration delay;

  @override
  State<StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AppMotion.mediumMs,
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(_fade);
    Future<void>.delayed(widget.delay * widget.index, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Subtle breathe/pulse when [active] (link live, armed, etc.).
class AlivePulse extends StatefulWidget {
  const AlivePulse({
    super.key,
    required this.active,
    required this.child,
    this.period = const Duration(milliseconds: 1500),
    this.minOpacity = 0.82,
    this.maxOpacity = 1.0,
    this.scale = 0.02,
  });

  final bool active;
  final Widget child;
  final Duration period;
  final double minOpacity;
  final double maxOpacity;
  final double scale;

  @override
  State<AlivePulse> createState() => _AlivePulseState();
}

class _AlivePulseState extends State<AlivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.period);
    _sync();
  }

  @override
  void didUpdateWidget(covariant AlivePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _ctrl.duration = widget.period;
    }
    _sync();
  }

  void _sync() {
    if (widget.active) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        final opacity =
            widget.minOpacity + (widget.maxOpacity - widget.minOpacity) * t;
        final s = 1.0 + widget.scale * t;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: s, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Gentle press feedback without changing button colors.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.scale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _down = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: widget.enabled ? () => setState(() => _down = false) : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: AppMotion.fastMs,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Animated number display for telemetry readouts.
class AnimatedMetricText extends StatelessWidget {
  const AnimatedMetricText({
    super.key,
    required this.value,
    required this.style,
    this.duration = AppMotion.fastMs,
  });

  final String value;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.35),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Text(
        value,
        key: ValueKey<String>(value),
        style: style,
      ),
    );
  }
}

/// Animated border glow when [active] (connected, armed, etc.).
class GlowWhenActive extends StatefulWidget {
  const GlowWhenActive({
    super.key,
    required this.active,
    required this.child,
    required this.color,
    this.borderRadius = 12,
    this.maxBlur = 14,
  });

  final bool active;
  final Widget child;
  final Color color;
  final double borderRadius;
  final double maxBlur;

  @override
  State<GlowWhenActive> createState() => _GlowWhenActiveState();
}

class _GlowWhenActiveState extends State<GlowWhenActive>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant GlowWhenActive oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active) {
      if (!_ctrl.isAnimating) _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = widget.active ? 0.35 + _ctrl.value * 0.45 : 0.0;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: t),
                      blurRadius: widget.maxBlur,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Top activity strip — pulses while [active] (serial poll, link, etc.).
class ActivityIndicatorBar extends StatefulWidget {
  const ActivityIndicatorBar({
    super.key,
    required this.active,
    required this.color,
    this.height = 2,
  });

  final bool active;
  final Color color;
  final double height;

  @override
  State<ActivityIndicatorBar> createState() => _ActivityIndicatorBarState();
}

class _ActivityIndicatorBarState extends State<ActivityIndicatorBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant ActivityIndicatorBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth * 0.22;
            final x = (_ctrl.value * (c.maxWidth + w)) - w;
            return SizedBox(
              height: widget.height,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Container(color: widget.color.withValues(alpha: 0.12)),
                  Positioned(
                    left: x,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            widget.color.withValues(alpha: 0.85),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Wizard / step content cross-fade.
class AnimatedWizardStep extends StatelessWidget {
  const AnimatedWizardStep({
    super.key,
    required this.stepKey,
    required this.child,
  });

  final Object stepKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.mediumMs,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(stepKey),
        child: child,
      ),
    );
  }
}

/// Serial log line entrance (recent lines only).
class SerialLogLine extends StatelessWidget {
  const SerialLogLine({
    super.key,
    required this.index,
    required this.total,
    required this.child,
  });

  final int index;
  final int total;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fromEnd = total - 1 - index;
    if (fromEnd > 12) return child;
    return StaggeredFadeIn(
      index: fromEnd.clamp(0, 12),
      delay: const Duration(milliseconds: 18),
      child: child,
    );
  }
}

/// Status badge with label cross-fade + optional pulse.
class AnimatedStatusBadge extends StatelessWidget {
  const AnimatedStatusBadge({
    super.key,
    required this.label,
    required this.color,
    required this.child,
    this.pulse = false,
  });

  final String label;
  final Color color;
  final Widget child;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return AlivePulse(
      active: pulse,
      period: const Duration(milliseconds: 1300),
      scale: 0.025,
      child: AnimatedSwitcher(
        duration: AppMotion.fastMs,
        child: KeyedSubtree(
          key: ValueKey<String>(label),
          child: child,
        ),
      ),
    );
  }
}

/// Very subtle CRT-style scan line (dark tabs only).
class SubtleScanOverlay extends StatefulWidget {
  const SubtleScanOverlay({
    super.key,
    this.enabled = true,
    this.opacity = 0.04,
  });

  final bool enabled;
  final double opacity;

  @override
  State<SubtleScanOverlay> createState() => _SubtleScanOverlayState();
}

class _SubtleScanOverlayState extends State<SubtleScanOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    if (widget.enabled) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant SubtleScanOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.enabled) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            painter: _ScanOverlayPainter(
              t: _ctrl.value,
              opacity: widget.opacity,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({required this.t, required this.opacity});

  final double t;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final y = t * size.height;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: opacity),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, y - 24, size.width, 48));
    canvas.drawRect(Rect.fromLTWH(0, y - 24, size.width, 48), paint);
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter old) =>
      old.t != t || old.opacity != opacity;
}

/// Elastic pop-in for icons and emphasis elements.
class BounceIn extends StatefulWidget {
  const BounceIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<BounceIn> createState() => _BounceInState();
}

class _BounceInState extends State<BounceIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    Future<void>.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// Small blinking dot for LIVE / link indicators.
class LiveDot extends StatelessWidget {
  const LiveDot({
    super.key,
    required this.active,
    required this.color,
    this.size = 6,
  });

  final bool active;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AlivePulse(
      active: active,
      scale: 0.12,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
