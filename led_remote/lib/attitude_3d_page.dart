import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'attitude_3d_demo_telemetry.dart';
import 'attitude_3d_motors.dart';
import 'serial_log_cache.dart';
import 'stm32_armed_telemetry.dart';
import 'theme/attitude_3d_theme.dart';
import 'theme/tx_palette.dart';
import 'widgets/app_motion.dart';
import 'widgets/attitude_3d_view.dart';
import 'widgets/debug_live_toggle.dart';
import 'widgets/tello_glb_view.dart';

enum _AttitudeViewMode { glb, wire }

/// Live 3D quad: attitude + per-motor `us=` from STM32 via ESP serial.
class Attitude3DPage extends StatefulWidget {
  const Attitude3DPage({
    super.key,
    required this.useEsp,
    required this.serialCache,
    this.onConnect,
    this.onSendCommand,
    this.commandBusy = false,
  });

  final bool useEsp;
  final SerialLogCache serialCache;
  final Future<bool> Function()? onConnect;
  final Future<void> Function(String label, String cmd)? onSendCommand;
  final bool commandBusy;

  @override
  State<Attitude3DPage> createState() => _Attitude3DPageState();
}

class _Attitude3DPageState extends State<Attitude3DPage>
    with SingleTickerProviderStateMixin {
  Stm32ArmedTelemetry _tel = const Stm32ArmedTelemetry();
  DateTime? _updatedAt;
  DateTime? _lastUiRefresh;
  late final Ticker _uiTicker;
  double _animTimeSec = 0;
  bool _lightMode = false;
  bool _fullscreen = false;
  bool _demoMode = false;
  _AttitudeViewMode _viewMode = _AttitudeViewMode.glb;
  bool _serialBufferHasUs = false;

  Stm32ArmedTelemetry get _displayTel =>
      _demoMode ? Attitude3DDemoTelemetry.at(_animTimeSec) : _tel;

  Attitude3DTheme get _theme =>
      _lightMode ? Attitude3DTheme.light : Attitude3DTheme.dark;

  @override
  void initState() {
    super.initState();
    widget.serialCache.addListener(_onSerial);
    widget.serialCache.setFastPoll(true);
    widget.serialCache.setTurboPoll(true);
    _parse(widget.serialCache.lines);
    if (widget.useEsp) {
      unawaited(widget.serialCache.refresh());
    }
    _uiTicker = createTicker((elapsed) {
      if (!mounted) return;
      _animTimeSec = elapsed.inMicroseconds / 1000000.0;
      // GLB prop spin runs in JS rAF — only repaint wireframe/demo each frame.
      if (_demoMode || _viewMode == _AttitudeViewMode.wire) {
        setState(() {});
      }
    })..start();
  }

  @override
  void dispose() {
    _uiTicker.dispose();
    widget.serialCache.removeListener(_onSerial);
    widget.serialCache.setTurboPoll(false);
    widget.serialCache.setFastPoll(false);
    super.dispose();
  }

  @override
  void didUpdateWidget(Attitude3DPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serialCache != widget.serialCache) {
      oldWidget.serialCache.removeListener(_onSerial);
      oldWidget.serialCache.setTurboPoll(false);
      oldWidget.serialCache.setFastPoll(false);
      widget.serialCache.addListener(_onSerial);
      widget.serialCache.setFastPoll(true);
      widget.serialCache.setTurboPoll(true);
      _parse(widget.serialCache.lines);
    }
  }

  void _onSerial() => _parse(widget.serialCache.lines);

  void _parse(List<String> lines) {
    final next = Stm32ArmedTelemetry.parse(lines);
    final bufferHasUs = Stm32ArmedTelemetry.bufferContainsMotorField(lines);
    final now = DateTime.now();
    final hasFc = next.hasAttitude || next.hasMotors;
    if (!hasFc && lines.isNotEmpty && (_tel.hasAttitude || _tel.hasMotors)) {
      // LIVE flood can briefly yield only UART tail chunks — keep last good FC snapshot.
      _updatedAt = now;
      setState(() {
        _serialBufferHasUs = bufferHasUs;
        _lastUiRefresh = now;
      });
      return;
    }
    _updatedAt = now;
    setState(() {
      _tel = next;
      _serialBufferHasUs = bufferHasUs;
      _lastUiRefresh = now;
    });
  }

  bool _hasLink() {
    if (_demoMode) return true;
    if (!widget.useEsp || _updatedAt == null) return false;
    if (!_tel.hasAttitude && !_tel.hasMotors) return false;
    return !_isStale();
  }

  bool _isStale() {
    final at = _updatedAt;
    if (at == null) return true;
    // LIVE debug ~10 Hz; allow ESP poll jitter + repeated identical lines.
    final limit = _tel.isLiveLine ? 1200 : 2800;
    return DateTime.now().difference(at).inMilliseconds > limit;
  }

  void _openFullscreen() => setState(() => _fullscreen = true);

  void _closeFullscreen() => setState(() => _fullscreen = false);

  Widget? _debugLiveChip() {
    final send = widget.onSendCommand;
    if (send == null) return null;
    return DebugLiveToggle(
      useEsp: widget.useEsp,
      busy: widget.commandBusy,
      serialCache: widget.serialCache,
      telemetry: _tel,
      onSend: send,
      compact: true,
    );
  }

  Widget _buildScene({
    required Attitude3DTheme theme,
    required bool link,
  }) {
    final tel = _displayTel;
    if (_viewMode == _AttitudeViewMode.glb) {
      return TelloGlbView(
        key: const ValueKey('tello_glb_view'),
        telemetry: tel,
        linkActive: link,
        theme: theme,
        animTimeSec: _animTimeSec,
        demoMode: _demoMode,
        lastUpdate: _demoMode ? DateTime.now() : _updatedAt,
      );
    }
    return Attitude3DView(
      key: const ValueKey('attitude_wire_view'),
      telemetry: tel,
      linkActive: link,
      theme: theme,
      lastUpdate: _demoMode ? DateTime.now() : _updatedAt,
      animTimeSec: _animTimeSec,
      demoMode: _demoMode,
    );
  }

  Widget _buildViewport({
    required Attitude3DTheme theme,
    required bool link,
    EdgeInsetsGeometry? margin,
    BorderRadius? borderRadius,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(8);
    final innerRadius = borderRadius == null
        ? BorderRadius.circular(7)
        : BorderRadius.circular(borderRadius.topLeft.x - 1);

    return Padding(
      padding: margin ?? const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: GlowWhenActive(
        active: link,
        color: theme.chipOkBorder,
        borderRadius: radius.topLeft.x,
        maxBlur: 16,
        child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.viewport,
          borderRadius: radius,
          border: Border.all(
            color: link ? theme.chipOkBorder : theme.viewportBorder,
          ),
        ),
        child: ClipRRect(
          borderRadius: innerRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildScene(theme: theme, link: link),
              Positioned(
                top: 8,
                left: 8,
                child: _ViewModeToggle(
                  mode: _viewMode,
                  theme: theme,
                  onToggle: () => setState(() {
                    _viewMode = _viewMode == _AttitudeViewMode.glb
                        ? _AttitudeViewMode.wire
                        : _AttitudeViewMode.glb;
                  }),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: _ViewportIconButton(
                  theme: theme,
                  icon: _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  label: _fullscreen ? 'EXIT' : 'FULL',
                  tooltip: _fullscreen ? 'Exit full screen' : 'Full screen',
                  onTap: _fullscreen ? _closeFullscreen : _openFullscreen,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final espOn = widget.useEsp;
    final link = _hasLink();
    final live = _demoMode || _tel.isLiveLine;
    final theme = _theme;
    final tel = _displayTel;

    final readout = _ReadoutBar(
      telemetry: tel,
      updatedAt: _demoMode ? DateTime.now() : _updatedAt,
      linkActive: link,
      espConnected: espOn,
      demoMode: _demoMode,
      serialBufferHasUs: _serialBufferHasUs,
      theme: theme,
    );

    if (_fullscreen) {
      return ColoredBox(
        color: theme.scaffold,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                child: Row(
                  children: [
                    Text(
                      '3D FULL SCREEN',
                      style: TextStyle(
                        color: TxPalette.amber,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    _ThemeToggle(
                      lightMode: _lightMode,
                      theme: theme,
                      onToggle: () => setState(() => _lightMode = !_lightMode),
                    ),
                    const SizedBox(width: 8),
                    _ViewModeToggle(
                      mode: _viewMode,
                      theme: theme,
                      onToggle: () => setState(() {
                        _viewMode = _viewMode == _AttitudeViewMode.glb
                            ? _AttitudeViewMode.wire
                            : _AttitudeViewMode.glb;
                      }),
                    ),
                    const SizedBox(width: 8),
                    _DemoToggle(
                      demoMode: _demoMode,
                      theme: theme,
                      onToggle: () => setState(() {
                        _demoMode = !_demoMode;
                      }),
                    ),
                    if (_debugLiveChip() != null) ...[
                      const SizedBox(width: 8),
                      _debugLiveChip()!,
                    ],
                    const SizedBox(width: 8),
                    _StatusChip(
                      label: _demoMode
                          ? 'DEMO'
                          : (!espOn
                              ? 'OFFLINE'
                              : !link
                                  ? (_tel.hasAttitude
                                      ? 'STALE'
                                      : (_tel.hasMotors ? 'MOTORS' : 'NO FC DATA'))
                                  : (live ? 'LIVE 10Hz' : 'POLL ~110ms')),
                      ok: link,
                      theme: theme,
                    ),
                    const SizedBox(width: 8),
                    _ViewportIconButton(
                      theme: theme,
                      icon: Icons.fullscreen_exit,
                      label: 'EXIT',
                      tooltip: 'Exit full screen',
                      onTap: _closeFullscreen,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildViewport(
                  theme: theme,
                  link: link,
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              readout,
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: theme.scaffold,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text(
                    '3D ATTITUDE',
                    style: TextStyle(
                      color: TxPalette.amber,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  if (!espOn)
                    TextButton(
                      onPressed: widget.onConnect == null
                          ? null
                          : () => unawaited(widget.onConnect!()),
                      child: const Text('Connect ESP'),
                    ),
                  _ThemeToggle(
                    lightMode: _lightMode,
                    theme: theme,
                    onToggle: () => setState(() => _lightMode = !_lightMode),
                  ),
                  const SizedBox(width: 8),
                  _ViewModeToggle(
                    mode: _viewMode,
                    theme: theme,
                    onToggle: () => setState(() {
                      _viewMode = _viewMode == _AttitudeViewMode.glb
                          ? _AttitudeViewMode.wire
                          : _AttitudeViewMode.glb;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _DemoToggle(
                    demoMode: _demoMode,
                    theme: theme,
                    onToggle: () => setState(() {
                      _demoMode = !_demoMode;
                    }),
                  ),
                  if (_debugLiveChip() != null) ...[
                    const SizedBox(width: 8),
                    _debugLiveChip()!,
                  ],
                  const SizedBox(width: 8),
                  _ViewportIconButton(
                    theme: theme,
                    icon: Icons.fullscreen,
                    label: 'FULL',
                    tooltip: 'Full screen 3D view',
                    onTap: _openFullscreen,
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: _demoMode
                        ? 'DEMO'
                        : (!espOn
                            ? 'OFFLINE'
                            : !link
                                ? (_tel.hasAttitude
                                    ? 'STALE'
                                    : (_tel.hasMotors ? 'MOTORS' : 'NO FC DATA'))
                                : (live ? 'LIVE 10Hz' : 'POLL ~110ms')),
                    ok: link,
                    theme: theme,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Tilt the rig — attR/attP should track here. Tap LIVE for 10 Hz debug stream '
                '(or Tune tab switch). Serial tab needs DISARMED | or LIVE | from ESP UART.',
                style: TextStyle(
                  color: theme.subtitle,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buildViewport(theme: theme, link: link),
            ),
            readout,
          ],
        ),
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({
    required this.mode,
    required this.theme,
    required this.onToggle,
  });

  final _AttitudeViewMode mode;
  final Attitude3DTheme theme;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final glb = mode == _AttitudeViewMode.glb;
    return Tooltip(
      message: glb ? 'Switch to wireframe view' : 'Switch to Tello GLB',
      child: Material(
        color: theme.toggleBg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.toggleBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  glb ? Icons.view_in_ar_outlined : Icons.grid_4x4,
                  size: 16,
                  color: TxPalette.amber,
                ),
                const SizedBox(width: 5),
                Text(
                  glb ? 'GLB' : 'WIRE',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 8,
                    letterSpacing: 1.2,
                    color: TxPalette.amber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoToggle extends StatelessWidget {
  const _DemoToggle({
    required this.demoMode,
    required this.theme,
    required this.onToggle,
  });

  final bool demoMode;
  final Attitude3DTheme theme;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: demoMode
          ? 'Turn off dummy telemetry'
          : 'Preview with dummy attitude + motors',
      child: Material(
        color: demoMode
            ? (theme.isLight
                ? const Color(0xFFDBEAFE)
                : const Color(0xFF1E3A5F))
            : theme.toggleBg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: demoMode ? TxPalette.amber : theme.toggleBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  demoMode ? Icons.science : Icons.science_outlined,
                  size: 16,
                  color: TxPalette.amber,
                ),
                const SizedBox(width: 5),
                Text(
                  demoMode ? 'DEMO ON' : 'DEMO',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 8,
                    letterSpacing: 1.2,
                    color: TxPalette.amber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewportIconButton extends StatelessWidget {
  const _ViewportIconButton({
    required this.theme,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final Attitude3DTheme theme;
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.toggleBg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.toggleBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: TxPalette.amber),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 8,
                    letterSpacing: 1.2,
                    color: TxPalette.amber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({
    required this.lightMode,
    required this.theme,
    required this.onToggle,
  });

  final bool lightMode;
  final Attitude3DTheme theme;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.toggleBg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.toggleBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                lightMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                size: 16,
                color: TxPalette.amber,
              ),
              const SizedBox(width: 6),
              Text(
                lightMode ? 'DARK' : 'LIGHT',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 8,
                  letterSpacing: 1.5,
                  color: TxPalette.amber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.ok,
    required this.theme,
  });

  final String label;
  final bool ok;
  final Attitude3DTheme theme;

  @override
  Widget build(BuildContext context) {
    final live = ok && label.toUpperCase().contains('LIVE');
    return AlivePulse(
      active: live,
      period: const Duration(milliseconds: 1200),
      scale: 0.03,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ok ? theme.chipOkBg : theme.chipBadBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: ok ? theme.chipOkBorder : theme.chipBadBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (live) ...[
              LiveDot(active: true, color: theme.chipOkText, size: 5),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: ok ? theme.chipOkText : theme.chipBadText,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadoutBar extends StatelessWidget {
  const _ReadoutBar({
    required this.telemetry,
    required this.updatedAt,
    required this.linkActive,
    required this.espConnected,
    required this.demoMode,
    required this.serialBufferHasUs,
    required this.theme,
  });

  final Stm32ArmedTelemetry telemetry;
  final DateTime? updatedAt;
  final bool linkActive;
  final bool espConnected;
  final bool demoMode;
  final bool serialBufferHasUs;
  final Attitude3DTheme theme;

  String _motorFeedLabel(Stm32ArmedTelemetry t) {
    if (t.hasMotors) return 'OK';
    if (serialBufferHasUs) return 'SERIAL ONLY';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    final age = updatedAt == null
        ? '—'
        : '${DateTime.now().difference(updatedAt!).inMilliseconds} ms ago';
    final motors = Attitude3DMotors.normalizeUs(t.motorUs);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      color: theme.readoutBar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _Cell('attR°', t.formatNum(t.attRollDeg, decimals: 2), theme: theme),
              _Cell('attP°', t.formatNum(t.attPitchDeg, decimals: 2), theme: theme),
              _Cell('yaw°', t.formatNum(t.yawDeg, decimals: 1), theme: theme),
              _Cell('armed', t.armed == true ? 'YES' : 'NO', theme: theme),
              _Cell(
                'src',
                demoMode
                    ? 'DEMO'
                    : (t.isLiveLine
                        ? 'LIVE'
                        : (t.hasAttitude ? 'DIS/ARM' : '—')),
                theme: theme,
              ),
              _Cell('age', (espConnected || demoMode) ? age : '—', theme: theme),
              if (espConnected && !demoMode)
                _Cell('mot feed', _motorFeedLabel(t), theme: theme),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (var i = 0; i < 4; i++)
                _MotorCell(index: i + 1, us: motors[i], theme: theme),
            ],
          ),
          if (espConnected &&
              !demoMode &&
              serialBufferHasUs &&
              !t.hasMotors) ...[
            const SizedBox(height: 4),
            Text(
              'Serial buffer has us= but 3D parser has no motors — check LIVE line format.',
              style: TextStyle(
                color: theme.isLight
                    ? const Color(0xFFB45309)
                    : const Color(0xFFFBBF24),
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (t.rawLine != null) ...[
            const SizedBox(height: 6),
            Text(
              t.rawLine!,
              style: TextStyle(
                color: theme.rawLine,
                fontSize: 8,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.label, this.value, {required this.theme});

  final String label;
  final String value;
  final Attitude3DTheme theme;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(color: theme.cellLabel),
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: AnimatedMetricText(
              value: value,
              style: TextStyle(
                color: theme.cellValue,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MotorCell extends StatelessWidget {
  const _MotorCell({
    required this.index,
    required this.us,
    required this.theme,
  });

  final int index;
  final int us;
  final Attitude3DTheme theme;

  @override
  Widget build(BuildContext context) {
    final active = Attitude3DMotors.activity(us);
    final valueColor = active > 0.05
        ? (theme.isLight ? const Color(0xFF15803D) : const Color(0xFF4ADE80))
        : theme.cellValue;

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
        children: [
          TextSpan(
            text: 'M$index ',
            style: TextStyle(color: theme.cellLabel),
          ),
          TextSpan(
            text: '$us µs',
            style: TextStyle(color: valueColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
