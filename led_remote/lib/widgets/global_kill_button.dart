import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_motion.dart';

/// Emergency stop: `rc off` + disarm. Use [compact] in side rail, [fullWidth] above nav.
class GlobalKillButton extends StatelessWidget {
  const GlobalKillButton({
    super.key,
    required this.onKill,
    this.busy = false,
    this.compact = false,
    this.fullWidth = false,
  });

  final VoidCallback onKill;
  final bool busy;
  final bool compact;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final fg = busy ? Colors.white38 : Colors.white;
    final label = Text(
      'KILL',
      style: TextStyle(
        color: fg,
        fontWeight: FontWeight.w800,
        fontSize: compact ? 9 : 14,
        letterSpacing: compact ? 1.5 : 2,
        fontFamily: 'monospace',
      ),
    );

    final button = Material(
      elevation: compact ? 2 : 4,
      shadowColor: Colors.black54,
      color: const Color(0xFFB91C1C),
      borderRadius: BorderRadius.circular(compact ? 6 : 8),
      child: InkWell(
        onTap: busy
            ? null
            : () {
                HapticFeedback.heavyImpact();
                onKill();
              },
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        child: Container(
          width: fullWidth ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 14,
            vertical: compact ? 10 : 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 6 : 8),
            border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
          ),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emergency_rounded, color: fg, size: 20),
                    const SizedBox(height: 4),
                    label,
                  ],
                )
              : Row(
                  mainAxisAlignment:
                      fullWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
                  mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Icon(Icons.emergency_rounded, color: fg, size: 22),
                    const SizedBox(width: 6),
                    label,
                  ],
                ),
        ),
      ),
    );

    return AlivePulse(
      active: !busy,
      period: const Duration(milliseconds: 2200),
      scale: 0.015,
      minOpacity: 0.92,
      child: button,
    );
  }
}
