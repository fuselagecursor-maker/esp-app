import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'control_page.dart';
import 'drone_http_client.dart';
import 'rc_command_line.dart';
import 'rc_teleop_sender.dart';
import 'theme/tx_palette.dart';
import 'widgets/app_motion.dart';
import 'widgets/tx_hold_to_arm.dart';

/// Per-axis sliders for `rc <thr%> <yaw> <pitch> <roll>` — bench / debug teleop.
class ManualControlPage extends StatefulWidget {
  const ManualControlPage({
    super.key,
    required this.useEsp,
    required this.baseUrl,
    required this.drone,
    required this.onNotify,
    this.initialThrottlePercent,
    this.initialArmed = false,
    this.armBusy = false,
    this.onArm,
    this.onDisarm,
    this.onThrottleReport,
  });

  final bool useEsp;
  final String baseUrl;
  final DroneHttpClient drone;
  final void Function(String message, {bool isError}) onNotify;
  final int? initialThrottlePercent;
  final bool initialArmed;
  final bool armBusy;
  final Future<bool> Function()? onArm;
  final Future<bool> Function()? onDisarm;
  final void Function(int throttlePercent)? onThrottleReport;

  @override
  State<ManualControlPage> createState() => _ManualControlPageState();
}

class _ManualControlPageState extends State<ManualControlPage> {
  static const _maxYawDps = 120;
  static const _maxPitchDps = 90;
  static const _maxRollDps = 90;
  static const _rcPeriod = Duration(milliseconds: 50);
  static const _rcHeartbeat = Duration(milliseconds: 220);

  double _throttlePct = 0;
  double _yawDps = 0;
  double _pitchDps = 0;
  double _rollDps = 0;
  bool _streamRc = true;
  bool _armed = false;

  Timer? _rcTimer;
  RcTeleopSender? _rcSender;
  String? _lastRcCommand;
  DateTime? _lastRcSentAt;

  @override
  void initState() {
    super.initState();
    final initialThr = widget.initialThrottlePercent;
    if (initialThr != null) {
      _throttlePct = initialThr.clamp(0, 100).toDouble();
    }
    _armed = widget.initialArmed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportThrottle();
      if (widget.useEsp && _armed) _startRcLink();
    });
  }

  @override
  void dispose() {
    _tearDownRc(sendOff: widget.useEsp);
    super.dispose();
  }

  @override
  void didUpdateWidget(ManualControlPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialArmed != widget.initialArmed &&
        widget.initialArmed != _armed) {
      _armed = widget.initialArmed;
      if (_armed && widget.useEsp) {
        _startRcLink();
      } else if (!_armed) {
        _tearDownRc(sendOff: widget.useEsp);
      }
    }
    if (!oldWidget.useEsp && widget.useEsp && _armed) {
      _startRcLink();
    } else if (oldWidget.useEsp && !widget.useEsp) {
      _tearDownRc(sendOff: false);
    }
  }

  void _reportThrottle() =>
      widget.onThrottleReport?.call(_throttlePct.round());

  String _rcCommand() => RcCommandLine.format(
        throttlePercent: _throttlePct.round(),
        yawDps: _yawDps,
        pitchDps: _pitchDps,
        rollDps: _rollDps,
      );

  void _startRcLink() {
    if (!widget.useEsp || _rcTimer != null) return;
    widget.drone.setBaseUrl(widget.baseUrl);
    _rcSender = RcTeleopSender(
      post: (cmd) => widget.drone.sendCommandLive(cmd),
      onError: (msg) {
        if (mounted) widget.onNotify(msg, isError: true);
      },
    );
    _rcTimer = Timer.periodic(_rcPeriod, (_) => _queueRc());
    _queueRc();
  }

  void _tearDownRc({required bool sendOff}) {
    _rcTimer?.cancel();
    _rcTimer = null;
    final sender = _rcSender;
    _rcSender = null;
    if (sender == null) return;
    widget.drone.setBaseUrl(widget.baseUrl);
    sender.dispose(finalCommand: sendOff ? 'rc off' : null);
  }

  void _queueRc() {
    if (!widget.useEsp || !_streamRc || !_armed || _rcSender == null) return;
    final cmd = _rcCommand();
    final now = DateTime.now();
    if (cmd == _lastRcCommand &&
        _lastRcSentAt != null &&
        now.difference(_lastRcSentAt!) < _rcHeartbeat) {
      return;
    }
    _lastRcCommand = cmd;
    _lastRcSentAt = now;
    _rcSender!.submit(cmd);
  }

  void _onValuesChanged() {
    _reportThrottle();
    setState(() {});
    _queueRc();
  }

  void _zeroRates() {
    HapticFeedback.selectionClick();
    setState(() {
      _yawDps = 0;
      _pitchDps = 0;
      _rollDps = 0;
    });
    _queueRc();
  }

  void _idleThrottle() {
    HapticFeedback.selectionClick();
    setState(() => _throttlePct = ControlPage.idleThrottlePercent.toDouble());
    _onValuesChanged();
  }

  void _resetAll() {
    HapticFeedback.mediumImpact();
    setState(() {
      _throttlePct = 0;
      _yawDps = 0;
      _pitchDps = 0;
      _rollDps = 0;
    });
    _onValuesChanged();
  }

  Future<void> _disarm() async {
    if (!widget.useEsp || widget.armBusy || !_armed) return;
    HapticFeedback.mediumImpact();
    setState(() => _armed = false);
    _tearDownRc(sendOff: true);
    try {
      await widget.onDisarm?.call();
    } catch (_) {}
  }

  Future<void> _armAfterHold() async {
    if (!widget.useEsp || widget.armBusy || _armed) return;
    final thr = _throttlePct.round().clamp(0, 100);
    if (!ControlPage.throttleAllowsArm(thr)) {
      widget.onNotify(ControlPage.throttleArmBlockMessage(thr), isError: true);
      return;
    }
    final confirm = await _confirmArm(context, thr);
    if (!confirm || !mounted) return;
    setState(() => _armed = true);
    final ok = await widget.onArm?.call() ?? false;
    if (!ok && mounted) {
      setState(() => _armed = false);
      _tearDownRc(sendOff: true);
      widget.onNotify('Arm failed — check Serial tab', isError: true);
    } else if (widget.useEsp) {
      _startRcLink();
      _queueRc();
    }
  }

  static Future<bool> _confirmArm(BuildContext context, int throttlePct) async {
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: TxPalette.panelDeep,
        title: Text('Confirm ARM', style: TextStyle(color: TxPalette.amber)),
        content: Text(
          'This will ARM the drone.\n\n'
          'Throttle: $throttlePct%\n\n'
          'Confirm only if props area is clear.',
          style: const TextStyle(color: TxPalette.labelMuted, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: TxPalette.amber)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: TxPalette.amber),
            child: const Text('ARM'),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const SubtleScanOverlay(enabled: true, opacity: 0.03),
        ColoredBox(
      color: TxPalette.panel,
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderBar(
                    useEsp: widget.useEsp,
                    streamRc: _streamRc,
                    commandPreview: _rcCommand(),
                    onStreamChanged: widget.useEsp
                        ? (v) async {
                            if (!v) {
                              try {
                                widget.drone.setBaseUrl(widget.baseUrl);
                                await widget.drone.sendCommandLive('rc off');
                              } catch (_) {}
                            }
                            if (!mounted) return;
                            setState(() => _streamRc = v);
                            if (v) _queueRc();
                          }
                        : null,
                    onZeroRates: _zeroRates,
                    onIdleThrottle: _idleThrottle,
                    onResetAll: _resetAll,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 8, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    Expanded(
                      child: _AxisSliderCard(
                        label: 'THROTTLE',
                        unit: '%',
                        value: _throttlePct,
                        display: _throttlePct.round().toString(),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        centered: false,
                        showZeroNudge: true,
                        rangeMinLabel: '0',
                        rangeMaxLabel: '100',
                        onChanged: widget.useEsp
                            ? (v) {
                                _throttlePct = v;
                                _onValuesChanged();
                              }
                            : null,
                        onNudge: widget.useEsp ? (d) => _nudgeThrottle(d) : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AxisSliderCard(
                        label: 'YAW',
                        unit: '°/s',
                        value: _yawDps,
                        display: _yawDps.round().toString(),
                        min: -_maxYawDps.toDouble(),
                        max: _maxYawDps.toDouble(),
                        divisions: _maxYawDps * 2,
                        centered: true,
                        onChanged: widget.useEsp
                            ? (v) {
                                _yawDps = v;
                                _onValuesChanged();
                              }
                            : null,
                        onNudge: widget.useEsp ? (d) => _nudgeAxis(() => _yawDps, (v) => _yawDps = v, _maxYawDps, d) : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AxisSliderCard(
                        label: 'PITCH',
                        unit: '°/s',
                        value: _pitchDps,
                        display: _pitchDps.round().toString(),
                        min: -_maxPitchDps.toDouble(),
                        max: _maxPitchDps.toDouble(),
                        divisions: _maxPitchDps * 2,
                        centered: true,
                        onChanged: widget.useEsp
                            ? (v) {
                                _pitchDps = v;
                                _onValuesChanged();
                              }
                            : null,
                        onNudge: widget.useEsp
                            ? (d) => _nudgeAxis(
                                  () => _pitchDps,
                                  (v) => _pitchDps = v,
                                  _maxPitchDps,
                                  d,
                                )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AxisSliderCard(
                        label: 'ROLL',
                        unit: '°/s',
                        value: _rollDps,
                        display: _rollDps.round().toString(),
                        min: -_maxRollDps.toDouble(),
                        max: _maxRollDps.toDouble(),
                        divisions: _maxRollDps * 2,
                        centered: true,
                        onChanged: widget.useEsp
                            ? (v) {
                                _rollDps = v;
                                _onValuesChanged();
                              }
                            : null,
                        onNudge: widget.useEsp
                            ? (d) => _nudgeAxis(
                                  () => _rollDps,
                                  (v) => _rollDps = v,
                                  _maxRollDps,
                                  d,
                                )
                            : null,
                      ),
                    ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.useEsp)
              _ManualArmColumn(
                armed: _armed,
                armBusy: widget.armBusy,
                onDisarm: _disarm,
                onArmHoldComplete: _armAfterHold,
              ),
          ],
        ),
      ),
    ),
      ],
    );
  }

  void _nudgeThrottle(double delta) {
    setState(() {
      _throttlePct = (_throttlePct + delta).clamp(0, 100);
    });
    _onValuesChanged();
  }

  void _nudgeAxis(
    double Function() read,
    void Function(double) write,
    int max,
    double delta,
  ) {
    setState(() {
      write((read() + delta).clamp(-max.toDouble(), max.toDouble()));
    });
    _onValuesChanged();
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.useEsp,
    required this.streamRc,
    required this.commandPreview,
    this.onStreamChanged,
    required this.onZeroRates,
    required this.onIdleThrottle,
    required this.onResetAll,
  });

  final bool useEsp;
  final bool streamRc;
  final String commandPreview;
  final ValueChanged<bool>? onStreamChanged;
  final VoidCallback onZeroRates;
  final VoidCallback onIdleThrottle;
  final VoidCallback onResetAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 4),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            Text(
              'MANUAL RC',
              style: TxPalette.labelStyle.copyWith(
                fontSize: 10,
                letterSpacing: 3,
                color: TxPalette.amber,
              ),
            ),
            const SizedBox(width: 12),
            if (!useEsp)
              Expanded(
                child: Text(
                  'Connect ESP on Home to stream',
                  style: TxPalette.labelStyle.copyWith(fontSize: 9),
                ),
              )
            else ...[
              Text(
                'STREAM RC',
                style: TxPalette.labelStyle.copyWith(fontSize: 9),
              ),
              const SizedBox(width: 6),
              _CompactStreamSwitch(
                value: streamRc,
                onChanged: onStreamChanged,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  commandPreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TxPalette.labelStyle.copyWith(
                    fontSize: 9,
                    color: TxPalette.labelMuted.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
            const Spacer(),
            _HeaderBtn(label: 'Rates 0', onPressed: onZeroRates),
            const SizedBox(width: 6),
            _HeaderBtn(label: 'Idle thr', onPressed: onIdleThrottle),
            const SizedBox(width: 6),
            _HeaderBtn(label: 'Reset all', onPressed: onResetAll),
          ],
        ),
      ),
    );
  }
}

/// Arm lever on the right edge (same idea as Control page) so sliders use full height.
class _ManualArmColumn extends StatelessWidget {
  const _ManualArmColumn({
    required this.armed,
    required this.armBusy,
    required this.onDisarm,
    required this.onArmHoldComplete,
  });

  final bool armed;
  final bool armBusy;
  final VoidCallback onDisarm;
  final Future<void> Function() onArmHoldComplete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TxPalette.panelDeep,
      child: Container(
        width: 80,
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: TxPalette.engraved, width: 1),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'ARM',
              style: TxPalette.labelStyle.copyWith(
                fontSize: 8,
                letterSpacing: 2,
                color: TxPalette.amber,
              ),
            ),
            const SizedBox(height: 10),
            TxHoldToArmSwitch(
              armed: armed,
              busy: armBusy,
              onDisarm: onDisarm,
              onArmHoldComplete: onArmHoldComplete,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                armed
                    ? 'Tap lever\nto DISARM'
                    : 'Hold lever\nup 1.2 s',
                textAlign: TextAlign.center,
                style: TxPalette.labelStyle.copyWith(
                  fontSize: 8,
                  height: 1.25,
                  color: armed ? TxPalette.armLed : TxPalette.labelMuted,
                ),
              ),
            ),
            if (armBusy) ...[
              const SizedBox(height: 8),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: TxPalette.amber,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fixed-size RC stream toggle — avoids Android [Switch.adaptive] painting huge
/// over the side rail when the header row is tight in landscape.
class _CompactStreamSwitch extends StatelessWidget {
  const _CompactStreamSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 24,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          activeTrackColor: TxPalette.amber.withValues(alpha: 0.5),
          activeThumbColor: TxPalette.amber,
        ),
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  const _HeaderBtn({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: TxPalette.amber,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: filled ? TxPalette.amber.withValues(alpha: 0.22) : TxPalette.panelDeep,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(label, style: TxPalette.labelStyle.copyWith(fontSize: 8)),
    );
  }
}

class _AxisSliderCard extends StatelessWidget {
  const _AxisSliderCard({
    required this.label,
    required this.unit,
    required this.value,
    required this.display,
    required this.min,
    required this.max,
    required this.divisions,
    required this.centered,
    this.showZeroNudge = false,
    this.rangeMinLabel,
    this.rangeMaxLabel,
    this.onChanged,
    this.onNudge,
  });

  final String label;
  final String unit;
  final double value;
  final String display;
  final double min;
  final double max;
  final int divisions;
  final bool centered;
  final bool showZeroNudge;
  final String? rangeMinLabel;
  final String? rangeMaxLabel;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onNudge;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final step = centered ? (max / 9).roundToDouble() : 5.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: TxPalette.panelDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TxPalette.engraved, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: TxPalette.labelStyle, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  display,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: TxPalette.amber,
                  ),
                ),
                const SizedBox(width: 4),
                Text(unit, style: TxPalette.labelStyle.copyWith(fontSize: 9)),
              ],
            ),
            if (rangeMaxLabel != null)
              Text(
                rangeMaxLabel!,
                style: TxPalette.labelStyle.copyWith(fontSize: 8),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 2),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: TxPalette.amber,
                    inactiveTrackColor: TxPalette.track,
                    thumbColor: const Color(0xFF6A7078),
                    overlayColor: TxPalette.amber.withValues(alpha: 0.12),
                    trackHeight: 5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: enabled ? onChanged : null,
                  ),
                ),
              ),
            ),
            if (rangeMinLabel != null)
              Text(
                rangeMinLabel!,
                style: TxPalette.labelStyle.copyWith(fontSize: 8),
                textAlign: TextAlign.center,
              ),
            if (onNudge != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _NudgeBtn(
                    icon: Icons.remove,
                    onTap: () => onNudge!(-step),
                  ),
                  if (centered || showZeroNudge)
                    _NudgeBtn(
                      icon: Icons.circle_outlined,
                      iconSize: 14,
                      onTap: () => onChanged?.call(centered ? 0 : min),
                    ),
                  _NudgeBtn(
                    icon: Icons.add,
                    onTap: () => onNudge!(step),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NudgeBtn extends StatelessWidget {
  const _NudgeBtn({
    required this.icon,
    required this.onTap,
    this.iconSize = 18,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TxPalette.track,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 40,
          height: 36,
          child: Icon(icon, size: iconSize, color: TxPalette.amber),
        ),
      ),
    );
  }
}
