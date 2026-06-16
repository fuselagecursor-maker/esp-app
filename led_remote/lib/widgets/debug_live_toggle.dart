import 'package:flutter/material.dart';

import 'app_motion.dart';
import '../fc_tune_commands.dart';
import '../serial_log_cache.dart';
import '../stm32_armed_telemetry.dart';
import '../theme/fc_tune_theme.dart';
import '../theme/tx_palette.dart';

/// Sends `debug live on/off` — shared by Tune and 3D tabs.
class DebugLiveToggle extends StatelessWidget {
  const DebugLiveToggle({
    super.key,
    required this.useEsp,
    required this.busy,
    required this.serialCache,
    required this.telemetry,
    required this.onSend,
    this.compact = false,
  });

  final bool useEsp;
  final bool busy;
  final SerialLogCache serialCache;
  final Stm32ArmedTelemetry telemetry;
  final Future<void> Function(String label, String cmd) onSend;
  final bool compact;

  Future<void> _set(BuildContext context, bool enabled) async {
    if (!useEsp || busy) return;
    serialCache.setDebugLivePreference(enabled);
    await onSend(
      enabled ? 'Debug live on' : 'Debug live off',
      enabled ? FcTuneCommands.debugLiveOn() : FcTuneCommands.debugLiveOff(),
    );
    await serialCache.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: serialCache,
      builder: (context, _) {
        final on = serialCache.debugLiveEffective(telemetry);
    if (compact) {
      return AlivePulse(
        active: on,
        period: const Duration(milliseconds: 1400),
        scale: 0.03,
        child: _DebugLiveChip(
          enabled: on,
          active: useEsp && !busy,
          onTap: useEsp && !busy ? () => _set(context, !on) : null,
        ),
      );
    }
        return _DebugLivePanel(
          useEsp: useEsp,
          enabled: on,
          busy: busy,
          onChanged: useEsp && !busy ? (v) => _set(context, v) : null,
        );
      },
    );
  }
}

class _DebugLiveChip extends StatelessWidget {
  const _DebugLiveChip({
    required this.enabled,
    required this.active,
    this.onTap,
  });

  final bool enabled;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled
          ? 'Debug live ON — 10 Hz LIVE stream (tap to turn off)'
          : 'Turn on debug live — 10 Hz LIVE stream for 3D motors',
      child: Material(
        color: enabled
            ? const Color(0xFF1E3A5F)
            : const Color(0xFF2A2E34),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Opacity(
            opacity: active ? 1 : 0.45,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: enabled ? TxPalette.amber : const Color(0xFF4A5058),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    enabled ? Icons.bolt : Icons.bolt_outlined,
                    size: 16,
                    color: enabled ? TxPalette.amber : TxPalette.labelMuted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    enabled ? 'LIVE ON' : 'LIVE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 8,
                      letterSpacing: 1.2,
                      color: enabled ? TxPalette.amber : TxPalette.labelMuted,
                      fontWeight: FontWeight.w600,
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

class _DebugLivePanel extends StatelessWidget {
  const _DebugLivePanel({
    required this.useEsp,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final bool useEsp;
  final bool enabled;
  final bool busy;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        dense: true,
        title: Text(
          'Debug live stream',
          style: c.labelStyle(fontSize: 10, color: c.accent),
        ),
        subtitle: Text(
          useEsp
              ? (enabled
                  ? 'ON — FC sends LIVE | @ ~10 Hz (faster 3D + motors)'
                  : 'OFF — slower DISARMED/ARMED poll (~1–2 Hz)')
              : 'Enable Live ESP on Home first',
          style: c.labelStyle(fontSize: 8, color: c.body).copyWith(height: 1.3),
        ),
        value: enabled,
        onChanged: onChanged,
        activeThumbColor: c.accent,
      ),
    );
  }
}

/// Compact chip styled for [Attitude3DTheme] headers (optional wrapper).
class DebugLiveAttitudeChip extends StatelessWidget {
  const DebugLiveAttitudeChip({
    super.key,
    required this.useEsp,
    required this.busy,
    required this.serialCache,
    required this.telemetry,
    required this.onSend,
  });

  final bool useEsp;
  final bool busy;
  final SerialLogCache serialCache;
  final Stm32ArmedTelemetry telemetry;
  final Future<void> Function(String label, String cmd) onSend;

  @override
  Widget build(BuildContext context) {
    return DebugLiveToggle(
      useEsp: useEsp,
      busy: busy,
      serialCache: serialCache,
      telemetry: telemetry,
      onSend: onSend,
      compact: true,
    );
  }
}
