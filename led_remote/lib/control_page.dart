import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arm_audio.dart';
import 'drone_http_client.dart';
import 'rc_stick_frame.dart';
import 'rc_teleop_sender.dart';
import 'stm32_telemetry.dart';
import 'widgets/fc_telemetry_hud.dart';
import 'theme/tx_palette.dart';
import 'tx_telemetry.dart';
import 'widgets/transmitter_controls.dart';
import 'widgets/transmitter_faceplate.dart';
import 'widgets/transmitter_gimbal.dart';
import 'widgets/app_motion.dart';
import 'widgets/tx_hold_to_arm.dart';

/// Machined aluminum transmitter control surface.
class ControlPage extends StatefulWidget {
  static const idleThrottlePercent = 30;

  /// Must be at or below this % to arm (slightly above idle for stick noise).
  static const maxThrottleBeforeArm = 35;

  static bool throttleAllowsArm(int throttlePercent) =>
      throttlePercent <= maxThrottleBeforeArm;

  static String throttleArmBlockMessage(int throttlePercent) =>
      'Throttle at $throttlePercent% — lower to 0% '
      '(≤$maxThrottleBeforeArm%) before arming';

  const ControlPage({
    super.key,
    required this.useEsp,
    required this.baseUrl,
    required this.drone,
    required this.onNotify,
    this.initialHeldThrottlePercent,
    this.initialArmed = false,
    this.onThrottleReport,
    this.fetchSerial,
    this.onArm,
    this.onDisarm,
    this.armBusy = false,
  });

  final bool useEsp;
  final String baseUrl;
  final DroneHttpClient drone;
  final void Function(String message, {bool isError}) onNotify;
  final int? initialHeldThrottlePercent;
  final bool initialArmed;
  final void Function(int throttlePercent)? onThrottleReport;
  final Future<List<String>> Function()? fetchSerial;
  final Future<bool> Function()? onArm;
  final Future<bool> Function()? onDisarm;
  final bool armBusy;

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  double _lx = 0;
  double _ly = 0;
  double _rx = 0;
  double _ry = 0;
  bool _armed = false;
  int _heldThrottlePct = 0;
  Timer? _rcTimer;
  Timer? _uiTimer;
  Timer? _telemetryTimer;
  bool _telemetryPolling = false;
  RcTeleopSender? _rcSender;
  String? _lastRcCommand;
  DateTime? _lastRcSentAt;
  int? _lastSentThr;
  FcTelemetrySnapshot? _fcTelemetry;
  DateTime? _fcTelemetryAt;

  /// STM32 needs ≥20 Hz; 300 ms gap zeros sticks. 20 Hz + dedupe eases ESP load.
  static const _rcPeriod = Duration(milliseconds: 50);
  static const _rcHeartbeat = Duration(milliseconds: 220);

  /// Rudder-only center detent (pitch/roll unchanged — full mixing allowed).
  static const _yawStickDeadzone = 0.05;

  static final _telemetryPeriod =
      Duration(milliseconds: kIsWeb ? 1800 : 1400);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialHeldThrottlePercent;
    if (initial != null) {
      _heldThrottlePct = initial.clamp(0, 100);
    }
    _armed = widget.initialArmed;
    ArmAudio.instance.ensureReady();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncThrottleReport();
      if (widget.useEsp && _armed) {
        _startRcLink();
        _startTelemetryPoll();
      }
    });
  }

  void _syncThrottleReport() =>
      widget.onThrottleReport?.call(_throttlePercent());

  @override
  void dispose() {
    _uiTimer?.cancel();
    _stopTelemetryPoll();
    _tearDownRc(sendOff: widget.useEsp);
    super.dispose();
  }

  @override
  void didUpdateWidget(ControlPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.useEsp && widget.useEsp && _armed) {
      _startRcLink();
      _startTelemetryPoll();
    } else if (oldWidget.useEsp && !widget.useEsp) {
      _tearDownRc(sendOff: false);
      _stopTelemetryPoll();
      if (mounted) {
        setState(() {
          _fcTelemetry = null;
          _fcTelemetryAt = null;
        });
      }
    }
  }

  void _startTelemetryPoll() {
    if (!widget.useEsp ||
        !_armed ||
        widget.fetchSerial == null ||
        _telemetryTimer != null) {
      return;
    }
    _telemetryTimer = Timer.periodic(_telemetryPeriod, (_) => _pollTelemetry());
    _pollTelemetry();
  }

  void _stopTelemetryPoll() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _telemetryPolling = false;
  }

  Future<void> _pollTelemetry() async {
    if (_telemetryPolling ||
        !widget.useEsp ||
        !_armed ||
        widget.fetchSerial == null) {
      return;
    }
    _telemetryPolling = true;
    try {
      final lines = await widget.fetchSerial!();
      if (!mounted) return;
      final snap = FcTelemetrySnapshot.parse(lines);
      if (_telemetrySame(snap, _fcTelemetry)) return;
      setState(() {
        _fcTelemetry = snap;
        _fcTelemetryAt = DateTime.now();
      });
    } catch (_) {
      // Silent on Control — Serial tab shows link errors.
    } finally {
      _telemetryPolling = false;
    }
  }

  RcStickFrame _stickFrame() => RcStickFrame(
        throttlePercent: _throttlePercent(),
        leftX: _lx,
        leftY: _ly,
        rightX: _rx,
        rightY: _ry,
        yawDeadzone: _yawStickDeadzone,
      );

  void _resetThrottleForArm() {
    _heldThrottlePct = 0;
    _ly = -1;
    _lx = 0;
  }

  void _resetSticksDisarmed() {
    _heldThrottlePct = 0;
    _ly = 0;
    _lx = 0;
    _rx = 0;
    _ry = 0;
  }

  /// Armed: bottom = 0%, top = 100% (linear, same idea as Manual slider).
  int _throttlePercent() {
    if (!_armed) {
      if (_ly == 0) return _heldThrottlePct.clamp(0, 100);
      if (_ly < 0) return 0;
      return (_ly * 100).round().clamp(0, 100);
    }

    if (_ly <= -0.98) return 0;

    final y = _ly.clamp(-1.0, 1.0);
    return ((y + 1) * 50).round().clamp(0, 100);
  }

  /// `rc <thr%> <yaw> <pitch> <roll>` @ 20 Hz — STM32 rate-mode RC.
  String _rcCommand() => _stickFrame().toRcCommand();

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

  /// Always refresh pending frame (timer must run even when values unchanged).
  void _queueRc() {
    if (!widget.useEsp || !_armed || _rcSender == null) return;
    if (_ly > -0.98) _heldThrottlePct = _throttlePercent();
    _syncThrottleReport();
    final thr = _throttlePercent();
    final cmd = _rcCommand();
    final now = DateTime.now();
    final thrChanged = thr != _lastSentThr;
    _lastSentThr = thr;
    if (!thrChanged &&
        cmd == _lastRcCommand &&
        _lastRcSentAt != null &&
        now.difference(_lastRcSentAt!) < _rcHeartbeat) {
      return;
    }
    _lastRcCommand = cmd;
    _lastRcSentAt = now;
    _rcSender!.submit(cmd);
  }

  static bool _telemetrySame(FcTelemetrySnapshot a, FcTelemetrySnapshot? b) {
    if (b == null) return false;
    return a.armed == b.armed &&
        a.hoverOn == b.hoverOn &&
        a.setpointRollDps == b.setpointRollDps &&
        a.setpointPitchDps == b.setpointPitchDps &&
        a.setpointYawDps == b.setpointYawDps &&
        a.rollDeg == b.rollDeg &&
        a.pitchDeg == b.pitchDeg &&
        a.yawDeg == b.yawDeg &&
        a.throttlePercent == b.throttlePercent &&
        a.latitude == b.latitude &&
        a.longitude == b.longitude;
  }

  void _scheduleUiUpdate() {
    if (!mounted) return;
    if (_uiTimer?.isActive ?? false) return;
    _uiTimer = Timer(const Duration(milliseconds: 33), () {
      _uiTimer = null;
      if (mounted) setState(() {});
    });
  }

  void _onStickChanged() {
    _syncThrottleReport();
    _queueRc();
    _scheduleUiUpdate();
  }

  Future<void> _disarm() async {
    if (widget.armBusy || !widget.useEsp || !mounted || !_armed) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _armed = false;
      _resetSticksDisarmed();
    });
    _lastSentThr = null;
    _stopTelemetryPoll();
    _tearDownRc(sendOff: true);
    await ArmAudio.instance.disarmed();
    if (!mounted) return;
    final ok = await widget.onDisarm?.call() ?? false;
    if (!ok && mounted) {
      setState(() => _armed = true);
      widget.onNotify('Disarm failed — switch back to SAFE', isError: true);
      if (widget.useEsp) {
        _startRcLink();
        _startTelemetryPoll();
      }
    }
  }

  Future<void> _armAfterHold() async {
    if (widget.armBusy || !widget.useEsp || !mounted || _armed) return;
    final thr = _throttlePercent();
    if (!ControlPage.throttleAllowsArm(thr)) {
      HapticFeedback.heavyImpact();
      widget.onNotify(ControlPage.throttleArmBlockMessage(thr), isError: true);
      return;
    }
    final confirm = await _confirmArm(context, thr);
    if (!confirm || !mounted) return;
    setState(() {
      _armed = true;
      _resetThrottleForArm();
      _lx = 0;
    });
    await ArmAudio.instance.armed();
    if (!mounted) return;
    final ok = await widget.onArm?.call() ?? false;
    if (!ok && mounted) {
      setState(() => _armed = false);
      _tearDownRc(sendOff: true);
      widget.onNotify('Arm failed — check Serial tab', isError: true);
    } else if (widget.useEsp) {
      _startRcLink();
      _startTelemetryPoll();
    }
  }

  static Future<bool> _confirmArm(BuildContext context, int throttlePct) async {
    final result = await showDialog<bool>(
      context: context,
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
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const SubtleScanOverlay(enabled: true, opacity: 0.035),
          ColoredBox(
        color: TxPalette.panel,
        child: TransmitterFaceplate(
          child: Column(
            children: [
              _TopDeck(
                telemetry: TxTelemetrySnapshot.fromControl(
                  throttlePercent: _throttlePercent(),
                  yaw: _lx,
                  pitch: _ry,
                  roll: _rx,
                ),
              ),
              Expanded(
                child: _MainDeck(
                  armed: _armed,
                  armBusy: widget.armBusy,
                  onDisarm: _disarm,
                  onArmHoldComplete: _armAfterHold,
                  fcTelemetry: _fcTelemetry,
                  fcTelemetryAt: _fcTelemetryAt,
                  hoverOn: _fcTelemetry?.hoverOn,
                  linkActive: widget.useEsp,
                  onLeftReleased: () {
                    setState(() {
                      _lx = 0;
                      if (_armed) {
                        _heldThrottlePct = _throttlePercent();
                      } else {
                        _ly = 0;
                        _heldThrottlePct = 0;
                      }
                    });
                    _onStickChanged();
                  },
                  onLeftChanged: (x, y) {
                    setState(() {
                      _lx = x;
                      _ly = y;
                    });
                    _onStickChanged();
                  },
                  onRightChanged: (x, y) {
                    setState(() {
                      _rx = x;
                      _ry = y;
                    });
                    _onStickChanged();
                  },
                  onRightReleased: () {
                    setState(() {
                      _rx = 0;
                      _ry = 0;
                    });
                    _onStickChanged();
                  },
                ),
              ),
              TxStatusBar(
                throttlePct: _throttlePercent(),
                linkActive: widget.useEsp,
              ),
              _RcLinkStrip(
                armed: _armed,
                linkActive: widget.useEsp,
                frame: _armed && widget.useEsp ? _stickFrame() : null,
                lastCommand: _lastRcCommand,
                telemetry: _fcTelemetry,
                leftX: _lx,
                leftY: _ly,
                rightX: _rx,
                rightY: _ry,
              ),
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }
}

class _TopDeck extends StatelessWidget {
  const _TopDeck({required this.telemetry});

  final TxTelemetrySnapshot telemetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          const TxFlipSwitch(label: 'SA'),
          const SizedBox(width: 10),
          const TxFlipSwitch(label: 'SB'),
          const Spacer(),
          TxAnalogGauge(label: 'THR', value: telemetry.throttle01),
          const SizedBox(width: 8),
          TxAnalogGauge(
            label: 'YAW',
            value: telemetry.yawNorm,
            centered: true,
          ),
          const SizedBox(width: 8),
          TxAnalogGauge(
            label: 'PIT',
            value: telemetry.pitchNorm,
            centered: true,
          ),
          const SizedBox(width: 8),
          TxAnalogGauge(
            label: 'ROL',
            value: telemetry.rollNorm,
            centered: true,
          ),
          const Spacer(),
          const TxFlipSwitch(label: 'SC'),
          const SizedBox(width: 10),
          const TxFlipSwitch(label: 'SD'),
        ],
      ),
    );
  }
}

class _MainDeck extends StatelessWidget {
  const _MainDeck({
    required this.armed,
    required this.armBusy,
    required this.onDisarm,
    required this.onArmHoldComplete,
    required this.linkActive,
    this.fcTelemetry,
    this.fcTelemetryAt,
    this.hoverOn,
    required this.onLeftChanged,
    required this.onLeftReleased,
    required this.onRightChanged,
    required this.onRightReleased,
  });

  final bool armed;
  final bool armBusy;
  final bool linkActive;
  final FcTelemetrySnapshot? fcTelemetry;
  final DateTime? fcTelemetryAt;
  final bool? hoverOn;
  final VoidCallback onDisarm;
  final Future<void> Function() onArmHoldComplete;
  final void Function(double x, double y) onLeftChanged;
  final VoidCallback onLeftReleased;
  final void Function(double x, double y) onRightChanged;
  final VoidCallback onRightReleased;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hoverOn == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(
              'Hover ON — STM32 ignores roll/pitch sticks; yaw still active',
              style: TxPalette.labelStyle.copyWith(
                color: TxPalette.amber,
                fontSize: 7,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        Expanded(
          child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _TrimColumn(labels: ['T1', 'T2']),
        Expanded(
          child: _StickZone(
            label: 'THROTTLE · RUDDER',
            throttleFromBottom: armed,
            holdThrottleOnRelease: armed,
            onChanged: onLeftChanged,
            onReleased: onLeftReleased,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            width: 72,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                FcTelemetryHud(
                  width: 72,
                  height: 58,
                  snapshot: fcTelemetry,
                  linkActive: linkActive,
                  lastUpdate: fcTelemetryAt,
                  appArmed: armed,
                  compact: true,
                ),
                const SizedBox(height: 8),
                TxHoldToArmSwitch(
                  armed: armed,
                  busy: armBusy,
                  onDisarm: onDisarm,
                  onArmHoldComplete: onArmHoldComplete,
                ),
              const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TxMicroToggle(label: 'T5'),
                    SizedBox(width: 12),
                    TxMicroToggle(label: 'T6'),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _StickZone(
            label: 'ELEVATOR · AILERON',
            onChanged: onRightChanged,
            onReleased: onRightReleased,
          ),
        ),
        const _TrimColumn(labels: ['T3', 'T4'], right: true),
      ],
          ),
        ),
      ],
    );
  }
}

/// Last `rc` line + FC setpoints (spR/spP/spY) for axis verification.
class _RcLinkStrip extends StatelessWidget {
  const _RcLinkStrip({
    required this.armed,
    required this.linkActive,
    required this.lastCommand,
    required this.telemetry,
    required this.leftX,
    required this.leftY,
    required this.rightX,
    required this.rightY,
    this.frame,
  });

  final bool armed;
  final bool linkActive;
  final RcStickFrame? frame;
  final String? lastCommand;
  final FcTelemetrySnapshot? telemetry;
  final double leftX;
  final double leftY;
  final double rightX;
  final double rightY;

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    final f = frame;
    final cmdLine = f == null
        ? null
        : 'CMD Y=${f.yawDps} P=${f.pitchDps} R=${f.rollDps} °/s';
    final stickLine = f == null
        ? null
        : 'sticks lx=${leftX.toStringAsFixed(2)} ly=${leftY.toStringAsFixed(2)} '
            'rx=${rightX.toStringAsFixed(2)} ry=${rightY.toStringAsFixed(2)}';
    final rightActive = rightX.abs() > 0.08 || rightY.abs() > 0.08;
    final yawLeak = f != null &&
        rightActive &&
        f.yawDps.abs() > 5 &&
        f.pitchDps.abs() < 5 &&
        f.rollDps.abs() < 5;
    final spMismatch = f != null && t != null && rightActive && (
          (f.rollDps.abs() > 8 &&
              (t.setpointRollDps?.abs() ?? 0) < 3 &&
              (t.setpointYawDps?.abs() ?? 0) > 8) ||
          (f.pitchDps.abs() > 8 &&
              (t.setpointPitchDps?.abs() ?? 0) < 3 &&
              (t.setpointYawDps?.abs() ?? 0) > 8));
    final spLine = t == null
        ? null
        : 'FC spY=${t.formatNum(t.setpointYawDps)} '
            'spP=${t.formatNum(t.setpointPitchDps)} '
            'spR=${t.formatNum(t.setpointRollDps)} °/s';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            armed && linkActive
                ? (lastCommand ?? 'rc …')
                : 'RC idle — arm + Live ESP to stream sticks',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              color: linkActive ? TxPalette.amber : TxPalette.labelMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (stickLine != null) ...[
            const SizedBox(height: 2),
            Text(
              stickLine,
              style: TxPalette.labelStyle.copyWith(fontSize: 7),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (cmdLine != null) ...[
            const SizedBox(height: 2),
            Text(
              cmdLine,
              style: TxPalette.labelStyle.copyWith(fontSize: 7),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (yawLeak) ...[
            const SizedBox(height: 2),
            Text(
              'Right stick active but only CMD Y — rudder bleed or lx≠0',
              style: TxPalette.labelStyle.copyWith(
                fontSize: 7,
                color: TxPalette.amber,
              ),
              maxLines: 2,
            ),
          ],
          if (spMismatch) ...[
            const SizedBox(height: 2),
            Text(
              'CMD roll≠0 but FC spY moves — STM32 rc parser/mixer, not stick map',
              style: TxPalette.labelStyle.copyWith(
                fontSize: 7,
                color: TxPalette.amber,
              ),
              maxLines: 2,
            ),
          ],
          if (spLine != null) ...[
            const SizedBox(height: 2),
            Text(
              spLine,
              style: TxPalette.labelStyle.copyWith(fontSize: 7),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _TrimColumn extends StatelessWidget {
  const _TrimColumn({required this.labels, this.right = false});

  final List<String> labels;
  final bool right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: right ? 4 : 10,
        right: right ? 10 : 4,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TxVerticalSlider(label: labels[0], value: 0.55),
          const SizedBox(height: 14),
          TxVerticalSlider(label: labels[1], value: 0.45),
        ],
      ),
    );
  }
}

class _StickZone extends StatelessWidget {
  const _StickZone({
    required this.label,
    required this.onChanged,
    required this.onReleased,
    this.showDetent = false,
    this.throttleFromBottom = false,
    this.holdThrottleOnRelease = false,
  });

  final String label;
  final void Function(double x, double y) onChanged;
  final VoidCallback onReleased;
  final bool showDetent;
  final bool throttleFromBottom;
  final bool holdThrottleOnRelease;

  static const _labelH = 14.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: _labelH,
          child: Center(
            child: Text(label, style: TxPalette.labelStyle),
          ),
        ),
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight,
                ) *
                    0.98;
                return SizedBox(
                  width: side,
                  height: side,
                  child: TransmitterGimbal(
                    key: ValueKey(
                      'gimbal-$throttleFromBottom-$holdThrottleOnRelease',
                    ),
                    showCenterDetent: showDetent && !throttleFromBottom,
                    throttleFromBottom: throttleFromBottom,
                    holdThrottleOnRelease: holdThrottleOnRelease,
                    onChanged: onChanged,
                    onReleased: onReleased,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
