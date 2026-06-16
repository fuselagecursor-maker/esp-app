import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fc_tune_commands.dart';
import 'serial_log_cache.dart';
import 'stm32_armed_telemetry.dart';
import 'theme/fc_tune_theme.dart';
import 'widgets/app_motion.dart';
import 'widgets/debug_live_toggle.dart';
import 'widgets/tune_serial_monitor.dart';
import 'widgets/tx_hold_to_arm.dart';

/// STM32 PID / hover / filters — no joysticks (Control tab for `rc` teleop).
class FcTunePage extends StatefulWidget {
  const FcTunePage({
    super.key,
    required this.useEsp,
    required this.armed,
    required this.busy,
    required this.armBusy,
    required this.onSendCommand,
    required this.onNotify,
    required this.onThrottleReport,
    required this.onArm,
    required this.onDisarm,
    required this.customCommandController,
    required this.onSendCustomLine,
    required this.onInsertCommand,
    this.serialCache,
    this.onClearSerialLog,
  });

  final bool useEsp;
  final bool armed;
  final bool busy;
  final bool armBusy;
  final Future<void> Function(String label, String cmd) onSendCommand;
  final void Function(String message, {bool isError}) onNotify;
  final void Function(int throttlePercent) onThrottleReport;
  final Future<bool> Function(int throttlePercent) onArm;
  final Future<bool> Function() onDisarm;
  final TextEditingController customCommandController;
  final Future<void> Function() onSendCustomLine;
  final void Function(String cmd) onInsertCommand;
  final SerialLogCache? serialCache;
  final Future<void> Function()? onClearSerialLog;

  @override
  State<FcTunePage> createState() => _FcTunePageState();
}

class _FcTunePageState extends State<FcTunePage> {
  static const _pidMinInterval = Duration(milliseconds: 100);

  double _throttlePct = FcTuneDefaults.idleThrottlePct.toDouble();
  bool _hoverOn = false;
  bool _notchEnabled = false;
  double _lpfHz = FcTuneDefaults.lpfHz.toDouble();
  double _notchHz = FcTuneDefaults.notchHz.toDouble();
  double _notchQ = FcTuneDefaults.notchQ;

  late _PidTriple _rateRoll;
  late _PidTriple _ratePitch;
  late _PidTriple _rateYaw;
  late _PidTriple _attRoll;
  late _PidTriple _attPitch;

  Stm32ArmedTelemetry _tel = const Stm32ArmedTelemetry();
  Timer? _livePollTimer;
  DateTime? _lastPidSend;
  bool _loadingDefaults = false;
  bool _helpExpanded = false;
  bool _defaultsHelpExpanded = false;
  bool _lightMode = false;
  int _tuneSending = 0;
  String? _lastSentCmd;
  String? _lastSendError;

  FcTuneColors get _colors => _lightMode ? FcTuneColors.light : FcTuneColors.dark;

  TxArmSwitchColors _armColors(FcTuneColors c) => TxArmSwitchColors(
        track: c.armTrack,
        border: c.armBorder,
        guard: c.armGuard,
        lever: c.armLever,
        leverBusy: c.armLeverBusy,
        amber: c.accent,
        labelMuted: c.label,
        armLed: c.arm,
      );

  @override
  void initState() {
    super.initState();
    _rateRoll = _PidTriple.rateRoll();
    _ratePitch = _PidTriple.ratePitch();
    _rateYaw = _PidTriple.rateYaw();
    _attRoll = _PidTriple.attRoll();
    _attPitch = _PidTriple.attPitch();
    widget.serialCache?.addListener(_onSerialUpdate);
    _livePollTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => widget.serialCache?.refresh(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncThrottle(_throttlePct.round());
      _refreshTelemetry();
      if (!widget.armed) _sendArmMaxFixed();
      widget.serialCache?.refresh();
    });
  }

  @override
  void didUpdateWidget(covariant FcTunePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serialCache != widget.serialCache) {
      oldWidget.serialCache?.removeListener(_onSerialUpdate);
      widget.serialCache?.addListener(_onSerialUpdate);
    }
    if (!widget.armed && _hoverOn) {
      setState(() => _hoverOn = false);
    }
  }

  @override
  void dispose() {
    _livePollTimer?.cancel();
    widget.serialCache?.removeListener(_onSerialUpdate);
    super.dispose();
  }

  void _onSerialUpdate() {
    if (!mounted) return;
    _refreshTelemetry();
  }

  void _refreshTelemetry() {
    final lines = widget.serialCache?.lines ?? const [];
    final next = Stm32ArmedTelemetry.parse(lines);
    if (next.hoverOn != null && next.hoverOn != _hoverOn) {
      _hoverOn = next.hoverOn!;
    }
    setState(() => _tel = next);
  }

  bool get _slidersEnabled => widget.useEsp && !widget.busy && _tuneSending == 0;

  Future<void> _send(String label, String cmd, {bool rateLimitPid = false}) async {
    if (!widget.useEsp) return;

    if (rateLimitPid && _lastPidSend != null) {
      final elapsed = DateTime.now().difference(_lastPidSend!);
      if (elapsed < _pidMinInterval) {
        await Future<void>.delayed(_pidMinInterval - elapsed);
      }
    }
    if (rateLimitPid) _lastPidSend = DateTime.now();

    if (cmd.length > FcTuneCommands.maxLineLength) {
      widget.onNotify(
        '$label: command too long (${cmd.length} > ${FcTuneCommands.maxLineLength}): $cmd',
        isError: true,
      );
      return;
    }

    setState(() {
      _tuneSending++;
      _lastSentCmd = cmd;
      _lastSendError = null;
    });
    try {
      await widget.onSendCommand(label, cmd);
    } catch (e) {
      if (mounted) {
        setState(() => _lastSendError = e.toString());
        widget.onNotify('$label: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _tuneSending--);
      }
    }
  }

  Future<void> _commitThrottle(int pct) async {
    final clamped = pct.clamp(0, 100);
    setState(() => _throttlePct = clamped.toDouble());
    _syncThrottle(clamped);
    await _send('Throttle', FcTuneCommands.throttlePercent(clamped));
  }

  Future<void> _sendPid(String label, _PidTriple axis) async {
    await _send(
      label,
      FcTuneCommands.pidAxis(axis.code, axis.kp, axis.ki, axis.kd),
      rateLimitPid: true,
    );
  }

  void _syncThrottle(int pct) {
    final clamped = pct.clamp(0, 100);
    widget.onThrottleReport(clamped);
  }

  Future<void> _sendArmMaxFixed() async {
    await _send('Arm max', FcTuneCommands.armMaxUs(FcTuneDefaults.armMaxUs));
  }

  Future<void> _rcOff() async {
    await _send('RC off', FcTuneCommands.rcOff());
  }

  Future<void> _refreshLive() async {
    await widget.serialCache?.refresh();
    _refreshTelemetry();
  }

  /// App session + STM32 telemetry (telemetry wins when present).
  bool get _showArmed => widget.armed || (_tel.armed == true);

  Future<void> _disarm() async {
    if (widget.armBusy || !widget.useEsp || !_showArmed) return;
    HapticFeedback.mediumImpact();
    await widget.onDisarm();
  }

  Future<void> _armAfterHold() async {
    if (widget.armBusy || !widget.useEsp || _showArmed) return;
    final confirm = await _confirmArm(context, _colors);
    if (!confirm || !mounted) return;
    final ok = await widget.onArm(FcTuneDefaults.idleThrottlePct);
    if (!mounted) return;
    if (ok) {
      setState(() => _throttlePct = FcTuneDefaults.idleThrottlePct.toDouble());
      _syncThrottle(FcTuneDefaults.idleThrottlePct);
      widget.onNotify(
        'Armed — motors ~${FcTuneDefaults.armIdleUs} µs. '
        'Then: Stabilize ON → throttle for bench.',
        isError: false,
      );
    } else {
      widget.onNotify('Arm failed — check Serial tab', isError: true);
    }
  }

  Future<void> _setStabilize(bool on) async {
    if (!widget.useEsp) return;
    if (on && !_showArmed) {
      widget.onNotify('Arm first, then Stabilize ON', isError: true);
      return;
    }
    setState(() => _hoverOn = on);
    await _send(
      on ? 'Stabilize ON' : 'Stabilize OFF',
      on ? FcTuneCommands.stabilizeOn() : FcTuneCommands.stabilizeOff(),
    );
  }

  Future<void> _pollPidFromFc() async {
    await _send('PID', FcTuneCommands.pidShow(), rateLimitPid: true);
    await widget.serialCache?.refresh();
    if (!mounted) return;
    _refreshTelemetry();
    _applyPidGainsFromSerial();
  }

  void _applyPidGainsFromSerial() {
    final gains = Stm32PidGains.parse(widget.serialCache?.lines ?? const []);
    if (gains == null || !mounted) return;
    setState(() {
      if (gains.rateRoll != null) _rateRoll.apply(gains.rateRoll!);
      if (gains.ratePitch != null) _ratePitch.apply(gains.ratePitch!);
      if (gains.rateYaw != null) _rateYaw.apply(gains.rateYaw!);
      if (gains.attRoll != null) _attRoll.apply(gains.attRoll!);
      if (gains.attPitch != null) _attPitch.apply(gains.attPitch!);
    });
    if (gains.isComplete) {
      widget.onNotify('PID sliders synced from FC (pid show)', isError: false);
    }
  }

  Future<void> _loadDefaults() async {
    if (!widget.useEsp || _loadingDefaults) return;
    setState(() => _loadingDefaults = true);
    try {
      for (final cmd in FcTuneCommands.loadDefaultsSequence()) {
        await widget.onSendCommand('Defaults', cmd);
      }
      setState(() {
        _throttlePct = FcTuneDefaults.idleThrottlePct.toDouble();
        _lpfHz = FcTuneDefaults.lpfHz.toDouble();
        _notchEnabled = false;
        _rateRoll = _PidTriple.rateRoll();
        _ratePitch = _PidTriple.ratePitch();
        _rateYaw = _PidTriple.rateYaw();
        _attRoll = _PidTriple.attRoll();
        _attPitch = _PidTriple.attPitch();
      });
      _syncThrottle(FcTuneDefaults.idleThrottlePct);
      widget.onNotify('Defaults sent to FC (disarm + RAM gains)', isError: false);
      await _pollPidFromFc();
    } finally {
      if (mounted) setState(() => _loadingDefaults = false);
    }
  }

  static Future<bool> _confirmArm(
    BuildContext context,
    FcTuneColors colors,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => Theme(
        data: colors.materialTheme(),
        child: AlertDialog(
          backgroundColor: colors.card,
          title: Text('Confirm ARM', style: TextStyle(color: colors.accent)),
          content: Text(
            'This will ARM the drone.\n\n'
            'FC sets throttle to 0% and motors to ~${FcTuneDefaults.armIdleUs} µs.\n'
            'Then use Stabilize ON for level hold.\n\n'
            'Props off for PID tuning. Clear the area.',
            style: TextStyle(color: colors.body, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: colors.accent)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.onAccent,
              ),
              child: const Text('ARM'),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  bool get _cmdEnabled => _slidersEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    return FcTuneTheme(
      colors: colors,
      child: Theme(
        data: colors.materialTheme(),
        child: ColoredBox(
          color: colors.scaffold,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  useEsp: widget.useEsp,
                  armed: _showArmed,
                  armBusy: widget.armBusy,
                  hoverOn: _hoverOn,
                  telArmed: _tel.armed,
                  lightMode: _lightMode,
                  armSwitchColors: _armColors(colors),
                  onToggleLight: () => setState(() => _lightMode = !_lightMode),
                  onArmHoldComplete: _armAfterHold,
                  onDisarm: _disarm,
                ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth > 720;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!widget.useEsp) _ConnectBanner(),
                        if (widget.serialCache != null) ...[
                          DebugLiveToggle(
                            useEsp: widget.useEsp,
                            busy: widget.busy || _tuneSending > 0,
                            serialCache: widget.serialCache!,
                            telemetry: _tel,
                            onSend: widget.onSendCommand,
                          ),
                          const SizedBox(height: 8),
                        ],
                        _LiveTelemetryPanel(
                          useEsp: widget.useEsp,
                          telemetry: _tel,
                          onRefresh: _refreshLive,
                        ),
                        const SizedBox(height: 12),
                        _AdvancedControlsCard(
                          enabled: _slidersEnabled,
                          onRcOff: _rcOff,
                          onRefresh: _refreshLive,
                          onPidPoll: _pollPidFromFc,
                          onPidReset: () => _send(
                            'PID reset',
                            FcTuneCommands.pidReset(),
                            rateLimitPid: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _UartCommandSection(
                          useEsp: widget.useEsp,
                          busy: widget.busy,
                          controller: widget.customCommandController,
                          onSend: widget.onSendCustomLine,
                          onInsert: widget.onInsertCommand,
                        ),
                        if (widget.serialCache != null) ...[
                          const SizedBox(height: 12),
                          TuneSerialMonitor(
                            useEsp: widget.useEsp,
                            busy: widget.busy,
                            serialCache: widget.serialCache!,
                            onClear: widget.onClearSerialLog ?? () async {},
                            onNotify: widget.onNotify,
                          ),
                        ],
                        const SizedBox(height: 12),
                        _BenchDefaultsHelp(
                          expanded: _defaultsHelpExpanded,
                          onToggle: () =>
                              setState(() => _defaultsHelpExpanded = !_defaultsHelpExpanded),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'SAFETY & THROTTLE',
                          subtitle:
                              'Sent to FC · arm forces 0% then use throttle after stabilize',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ThrottleRow(
                                label: 'Throttle command (after arm + stabilize)',
                                subtitle: 'Use + / − only (slider is display-only)',
                                buttonsOnly: true,
                                enabled: _slidersEnabled,
                                value: _throttlePct,
                                min: 0,
                                max: 100,
                                divisions: 100,
                                unit: '%',
                                onChanged: (v) => setState(() => _throttlePct = v),
                                onCommit: (v) => _commitThrottle(v.round()),
                              ),
                              const SizedBox(height: 8),
                              _LastSentLine(cmd: _lastSentCmd, error: _lastSendError),
                              const SizedBox(height: 6),
                              Text(
                                'armmax ${FcTuneDefaults.armMaxUs} µs (set disarmed) · arm idle ${FcTuneDefaults.armIdleUs} µs',
                                style: FcTuneTheme.of(context)
                                    .labelStyle(fontSize: 8, color: context.fc.body),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'STABILIZE (LEVEL HOLD)',
                          subtitle:
                              'arm → 1050 µs all motors · stabilize on → hov=1 · then throttle N',
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _hoverOn
                                      ? 'Stabilize ON (hov=1, att 0/0)'
                                      : 'Throttle only (hov=0)',
                                  style: FcTuneTheme.of(context).labelStyle(fontSize: 9),
                                ),
                              ),
                              Switch(
                                value: _hoverOn,
                                onChanged: _slidersEnabled
                                    ? (v) => _setStabilize(v)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'RATE PID (send to FC)',
                          subtitle:
                              'Sliders = bench starting gains (Kp/Kd ≠ 0 is normal). '
                              'Live PID r/p/y above = controller output, not these gains.',
                          trailing: _PidToolbar(
                            enabled: widget.useEsp && _tuneSending == 0,
                            busy: widget.busy || _tuneSending > 0,
                            onReset: () => _send('PID reset', FcTuneCommands.pidReset(), rateLimitPid: true),
                            onPoll: _pollPidFromFc,
                          ),
                          child: wide
                              ? IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(child: _buildPidCard('ROLL', _rateRoll)),
                                      const SizedBox(width: 8),
                                      Expanded(child: _buildPidCard('PITCH', _ratePitch)),
                                      const SizedBox(width: 8),
                                      Expanded(child: _buildPidCard('YAW', _rateYaw)),
                                    ],
                                  ),
                                )
                              : Column(
                                  children: [
                                    _buildPidCard('ROLL', _rateRoll),
                                    const SizedBox(height: 8),
                                    _buildPidCard('PITCH', _ratePitch),
                                    const SizedBox(height: 8),
                                    _buildPidCard('YAW', _rateYaw),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'ATTITUDE PID',
                          subtitle: 'Outer loop · with stabilize on',
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _buildPidCard('ROLL ∠', _attRoll)),
                                    const SizedBox(width: 8),
                                    Expanded(child: _buildPidCard('PITCH ∠', _attPitch)),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildPidCard('ROLL ∠', _attRoll),
                                    const SizedBox(height: 8),
                                    _buildPidCard('PITCH ∠', _attPitch),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'GYRO FILTER',
                          subtitle: 'LPF anytime · notch with props at motor buzz Hz',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ThrottleRow(
                                label: 'LPF (Hz, 0 = off)',
                                enabled: _slidersEnabled,
                                value: _lpfHz,
                                min: 0,
                                max: 200,
                                divisions: 40,
                                unit: ' Hz',
                                onChanged: (v) => setState(() => _lpfHz = v),
                                onCommit: (v) => _send(
                                  'LPF',
                                  FcTuneCommands.filterLpf(v.round()),
                                  rateLimitPid: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Notch filter',
                                  style: FcTuneTheme.of(context).labelStyle(fontSize: 9),
                                ),
                                value: _notchEnabled,
                                onChanged: _slidersEnabled
                                    ? (v) {
                                        setState(() => _notchEnabled = v);
                                        if (!v) {
                                          _send('Notch off', FcTuneCommands.filterNotchOff(), rateLimitPid: true);
                                        }
                                      }
                                    : null,
                              ),
                              if (_notchEnabled) ...[
                                _ThrottleRow(
                                  label: 'Notch Hz',
                                  enabled: _slidersEnabled,
                                  value: _notchHz,
                                  min: 40,
                                  max: 400,
                                  divisions: 72,
                                  unit: ' Hz',
                                  onChanged: (v) => setState(() => _notchHz = v),
                                  onCommit: (v) => _send(
                                    'Notch',
                                    FcTuneCommands.filterNotch(v.round(), _notchQ),
                                    rateLimitPid: true,
                                  ),
                                ),
                                _ParamSliderRow(
                                  enabled: _slidersEnabled,
                                  value: _notchQ,
                                  min: 5,
                                  max: 50,
                                  divisions: 45,
                                  display: _notchQ.toStringAsFixed(0),
                                  step: 1,
                                  onChanged: (v) => setState(() => _notchQ = v),
                                  onCommit: (v) => _send(
                                    'Notch Q',
                                    FcTuneCommands.filterNotch(_notchHz.round(), v),
                                    rateLimitPid: true,
                                  ),
                                  onReset: () {},
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _cmdEnabled && !_loadingDefaults
                                    ? _loadDefaults
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: FcTuneTheme.of(context).accent,
                                  foregroundColor: FcTuneTheme.of(context).onAccent,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: Text(
                                  _loadingDefaults ? 'SENDING…' : 'LOAD DEFAULTS',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _BenchHelp(expanded: _helpExpanded, onToggle: () {
                          setState(() => _helpExpanded = !_helpExpanded);
                        }),
                      ],
                    );
                  },
                ),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPidCard(String title, _PidTriple axis) {
    final cmd = FcTuneCommands.pidAxis(axis.code, axis.kp, axis.ki, axis.kd);
    return _PidAxisCard(
      title: title,
      commandPreview: cmd,
      enabled: _slidersEnabled,
      values: axis,
      onChanged: () => setState(() {}),
      onApply: () => _sendPid('$title PID', axis),
      onReset: () {
        axis.resetToDefaults();
        setState(() {});
        _sendPid('$title reset', axis);
      },
    );
  }
}

class _PidTriple {
  _PidTriple({
    required this.code,
    required this.kp,
    required this.ki,
    required this.kd,
    required this.defKp,
    required this.defKi,
    required this.defKd,
  });

  final String code;
  double kp;
  double ki;
  double kd;
  final double defKp;
  final double defKi;
  final double defKd;

  void resetToDefaults() {
    kp = defKp;
    ki = defKi;
    kd = defKd;
  }

  void apply(List<double> kpkikd) {
    if (kpkikd.length < 3) return;
    kp = kpkikd[0];
    ki = kpkikd[1];
    kd = kpkikd[2];
  }

  factory _PidTriple.rateRoll() => _PidTriple(
        code: 'r',
        kp: FcTuneDefaults.rateRollKp,
        ki: FcTuneDefaults.rateRollKi,
        kd: FcTuneDefaults.rateRollKd,
        defKp: FcTuneDefaults.rateRollKp,
        defKi: FcTuneDefaults.rateRollKi,
        defKd: FcTuneDefaults.rateRollKd,
      );

  factory _PidTriple.ratePitch() => _PidTriple(
        code: 'p',
        kp: FcTuneDefaults.ratePitchKp,
        ki: FcTuneDefaults.ratePitchKi,
        kd: FcTuneDefaults.ratePitchKd,
        defKp: FcTuneDefaults.ratePitchKp,
        defKi: FcTuneDefaults.ratePitchKi,
        defKd: FcTuneDefaults.ratePitchKd,
      );

  factory _PidTriple.rateYaw() => _PidTriple(
        code: 'y',
        kp: FcTuneDefaults.rateYawKp,
        ki: FcTuneDefaults.rateYawKi,
        kd: FcTuneDefaults.rateYawKd,
        defKp: FcTuneDefaults.rateYawKp,
        defKi: FcTuneDefaults.rateYawKi,
        defKd: FcTuneDefaults.rateYawKd,
      );

  factory _PidTriple.attRoll() => _PidTriple(
        code: 'ar',
        kp: FcTuneDefaults.attRollKp,
        ki: FcTuneDefaults.attRollKi,
        kd: FcTuneDefaults.attRollKd,
        defKp: FcTuneDefaults.attRollKp,
        defKi: FcTuneDefaults.attRollKi,
        defKd: FcTuneDefaults.attRollKd,
      );

  factory _PidTriple.attPitch() => _PidTriple(
        code: 'ap',
        kp: FcTuneDefaults.attPitchKp,
        ki: FcTuneDefaults.attPitchKi,
        kd: FcTuneDefaults.attPitchKd,
        defKp: FcTuneDefaults.attPitchKp,
        defKi: FcTuneDefaults.attPitchKi,
        defKd: FcTuneDefaults.attPitchKd,
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.useEsp,
    required this.armed,
    required this.armBusy,
    required this.hoverOn,
    required this.telArmed,
    required this.lightMode,
    required this.onToggleLight,
    required this.armSwitchColors,
    required this.onArmHoldComplete,
    required this.onDisarm,
  });

  final bool useEsp;
  final bool armed;
  final bool armBusy;
  final bool hoverOn;
  final bool? telArmed;
  final bool lightMode;
  final VoidCallback onToggleLight;
  final TxArmSwitchColors armSwitchColors;
  final Future<void> Function() onArmHoldComplete;
  final VoidCallback onDisarm;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final canDisarm = useEsp && !armBusy && armed;
    final statusArmed = telArmed ?? armed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          Text(
            'FC TUNE',
            style: c.labelStyle(fontSize: 11, letterSpacing: 3, color: c.accent),
          ),
          const SizedBox(width: 8),
          _StatusChip(
            label: statusArmed ? 'ARMED' : 'DISARMED',
            color: statusArmed ? c.arm : c.label,
          ),
          if (hoverOn) ...[
            const SizedBox(width: 6),
            _StatusChip(label: 'HOV', color: c.accent),
          ],
          const Spacer(),
          _LightModeToggle(lightMode: lightMode, onToggle: onToggleLight),
          const SizedBox(width: 8),
          _LandscapeArmBar(
            useEsp: useEsp,
            armed: armed,
            armBusy: armBusy,
            armSwitchColors: armSwitchColors,
            onArmHoldComplete: onArmHoldComplete,
            onDisarm: onDisarm,
            canDisarm: canDisarm,
          ),
        ],
      ),
    );
  }
}

class _LightModeToggle extends StatelessWidget {
  const _LightModeToggle({required this.lightMode, required this.onToggle});

  final bool lightMode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                lightMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                size: 16,
                color: c.accent,
              ),
              const SizedBox(width: 6),
              Text(
                lightMode ? 'DARK' : 'LIGHT',
                style: c.labelStyle(fontSize: 8, letterSpacing: 1.5, color: c.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final pulse = label == 'ARMED' || label == 'LIVE' || label.startsWith('hov=');
    return AnimatedStatusBadge(
      label: label,
      color: color,
      pulse: pulse,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: c.isLight ? 0.14 : 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pulse) ...[
              LiveDot(active: true, color: color, size: 4),
              const SizedBox(width: 4),
            ],
            Text(label, style: c.labelStyle(fontSize: 7, color: color)),
          ],
        ),
      ),
    );
  }
}

class _LandscapeArmBar extends StatelessWidget {
  const _LandscapeArmBar({
    required this.useEsp,
    required this.armed,
    required this.armBusy,
    required this.armSwitchColors,
    required this.onArmHoldComplete,
    required this.onDisarm,
    required this.canDisarm,
  });

  final bool useEsp;
  final bool armed;
  final bool armBusy;
  final TxArmSwitchColors armSwitchColors;
  final Future<void> Function() onArmHoldComplete;
  final VoidCallback onDisarm;
  final bool canDisarm;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return GlowWhenActive(
      active: armed,
      color: c.arm,
      borderRadius: 6,
      child: Material(
      color: c.card,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: armed ? c.arm.withValues(alpha: 0.45) : c.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TxHoldToArmSwitch(
              armed: armed,
              busy: armBusy || !useEsp,
              colors: armSwitchColors,
              onDisarm: onDisarm,
              onArmHoldComplete: onArmHoldComplete,
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: canDisarm ? onDisarm : null,
              style: FilledButton.styleFrom(
                backgroundColor: c.disarm,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('DISARM', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10)),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _LiveTelemetryPanel extends StatelessWidget {
  const _LiveTelemetryPanel({
    required this.useEsp,
    required this.telemetry,
    required this.onRefresh,
  });

  final bool useEsp;
  final Stm32ArmedTelemetry telemetry;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = telemetry;

    if (!useEsp) {
      return _SectionCard(
        title: 'LIVE FROM DRONE',
        subtitle: 'STM32 UART via ESP only — enable Live ESP on Home',
        child: Text(
          'No link. Values below are not shown until serial data arrives.',
          style: c.labelStyle(fontSize: 9, color: c.body).copyWith(height: 1.35),
        ),
      );
    }

    if (!t.hasLiveFlight) {
      return _SectionCard(
        title: 'LIVE FROM DRONE',
        subtitle: 'Waiting for ARMED | or DISARMED | line on serial',
        trailing: TextButton(
          onPressed: onRefresh,
          child: Text('Refresh', style: TextStyle(color: c.accent, fontSize: 10)),
        ),
        child: Text(
          'No flight telemetry yet. Arm on bench or check Serial tab for '
          'ARMED | … lines. Nothing here is simulated.',
          style: c.labelStyle(fontSize: 9, color: c.body).copyWith(height: 1.35),
        ),
      );
    }

    final armed = t.armed == true;
    final linkOk = t.isLinkFresh;

    return _SectionCard(
      title: 'LIVE FROM DRONE',
      subtitle: 'Parsed from STM32 ${t.formatAge()} · ${linkOk ? 'stream OK' : 'stale — tap Refresh'}',
      trailing: TextButton(
        onPressed: onRefresh,
        child: Text('Refresh', style: TextStyle(color: c.accent, fontSize: 10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _StatusChip(
                label: armed ? 'ARMED' : 'DISARMED',
                color: armed ? c.arm : c.label,
              ),
              if (t.hoverOn != null)
                _StatusChip(label: 'hov=${t.hoverOn! ? 1 : 0}', color: c.accent),
              _StatusChip(
                label: linkOk ? 'LIVE' : 'STALE',
                color: linkOk ? c.arm : c.disarm,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('IMU & attitude', style: c.labelStyle(fontSize: 7, color: c.accent)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _TelCell('ax', t.formatNum(t.ax, decimals: 2)),
              _TelCell('ay', t.formatNum(t.ay, decimals: 2)),
              _TelCell('az', t.formatNum(t.az, decimals: 2)),
              _TelCell('|a|', t.formatNum(t.accelMagMps2, decimals: 2)),
              _TelCell('gx', t.formatNum(t.gx)),
              _TelCell('gy', t.formatNum(t.gy)),
              _TelCell('gz', t.formatNum(t.gz)),
              _TelCell('rate R', t.formatNum(t.measRateRoll)),
              _TelCell('rate P', t.formatNum(t.measRatePitch)),
              _TelCell('rate Y', t.formatNum(t.measRateYaw)),
              _TelCell('attR°', t.formatNum(t.attRollDeg, decimals: 2)),
              _TelCell('attP°', t.formatNum(t.attPitchDeg, decimals: 2)),
              _TelCell('yaw°', t.formatNum(t.yawDeg, decimals: 2)),
              if (t.flightMode != null) _TelCell('mode', t.flightMode!),
              if (t.imuSeq != null) _TelCell('seq', '${t.imuSeq}'),
            ],
          ),
          if (t.rawAccel.isNotEmpty || t.rawGyro.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'rawA: ${t.rawAccel.join(' ')}  gR: ${t.rawGyro.join(' ')}',
              style: c.labelStyle(fontSize: 7).copyWith(fontFamily: 'monospace'),
            ),
          ],
          const SizedBox(height: 10),
          Text('Control loop (live)', style: c.labelStyle(fontSize: 7, color: c.accent)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _TelCell('spR', t.formatNum(t.spRollDps)),
              _TelCell('spP', t.formatNum(t.spPitchDps)),
              _TelCell('spY', t.formatNum(t.spYawDps)),
              _TelCell('PID r', t.formatNum(t.pidRoll, decimals: 2)),
              _TelCell('PID p', t.formatNum(t.pidPitch, decimals: 2)),
              _TelCell('PID y', t.formatNum(t.pidYaw, decimals: 2)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'PID r/p/y = rate loop output (deg/s). spR/P/Y = rate setpoints. '
            'PID POLL syncs Kp/Ki/Kd sliders from pid show.',
            style: c.labelStyle(fontSize: 7, color: c.body).copyWith(height: 1.3),
          ),
          if (t.motorPct.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Motors', style: c.labelStyle(fontSize: 7, color: c.accent)),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < t.motorPct.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _MotorBar(label: 'M$i', pct: t.motorPct[i].round()),
                  ),
                ],
              ],
            ),
          ],
          if (t.motorUs.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'µs: ${t.motorUs.join(' ')}',
              style: c.labelStyle(fontSize: 7).copyWith(fontFamily: 'monospace'),
            ),
          ],
          const SizedBox(height: 10),
          Text('Sensors', style: c.labelStyle(fontSize: 7, color: c.accent)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _TelCell('T °C', t.formatNum(t.tempC, decimals: 2)),
              _TelCell('P hPa', t.formatNum(t.pressureHpa, decimals: 1)),
            ],
          ),
          if (t.estimator != null || t.gpsStatus != null || t.magStatus != null) ...[
            const SizedBox(height: 8),
            if (t.estimator != null)
              Text('EST: ${t.estimator}', style: _statusLineStyle(c)),
            if (t.magStatus != null)
              Text('MAG: ${t.magStatus}', style: _statusLineStyle(c)),
            if (t.gpsStatus != null)
              Text('GPS: ${t.gpsStatus}', style: _statusLineStyle(c)),
          ],
          if (t.rawLine != null) ...[
            const SizedBox(height: 8),
            Text(
              t.rawLine!,
              style: c.labelStyle(fontSize: 7).copyWith(
                fontFamily: 'monospace',
                color: armed ? c.arm : c.label,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static TextStyle _statusLineStyle(FcTuneColors c) =>
      c.labelStyle(fontSize: 7, color: c.body).copyWith(fontFamily: 'monospace', height: 1.25);
}

/// Raw UART lines to STM32 (same controller as Home tab).
class _UartCommandSection extends StatelessWidget {
  const _UartCommandSection({
    required this.useEsp,
    required this.busy,
    required this.controller,
    required this.onSend,
    required this.onInsert,
  });

  final bool useEsp;
  final bool busy;
  final TextEditingController controller;
  final Future<void> Function() onSend;
  final void Function(String cmd) onInsert;

  static const _quickCommands = [
    'disarm',
    'armmax 2000',
    'arm',
    'stabilize on',
    'stabilize off',
    'throttle 0',
    'pid show',
    'pid reset',
    'rc off',
    'filter lpf 80',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final enabled = useEsp && !busy;

    return _SectionCard(
      title: 'UART COMMANDS',
      subtitle: 'Same as Home · one line per Send (max 31 chars on ESP)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final cmd in _quickCommands)
                _CmdChip(
                  label: cmd,
                  enabled: enabled,
                  onTap: () => onInsert(cmd),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            enabled: enabled,
            maxLines: 4,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
              color: c.body,
            ),
            decoration: InputDecoration(
              hintText: 'disarm, armmax 2000, arm, stabilize on, throttle 45, …',
              hintStyle: c.labelStyle(fontSize: 9, color: c.label),
              filled: true,
              fillColor: c.cardInset,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: c.accent),
              ),
              contentPadding: const EdgeInsets.all(10),
            ),
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: enabled ? onSend : null,
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text(
              'SEND',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _CmdChip extends StatelessWidget {
  const _CmdChip({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Material(
      color: c.chipFill,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: c.border.withValues(alpha: 0.7)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: enabled ? c.accent : c.label,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdvancedControlsCard extends StatelessWidget {
  const _AdvancedControlsCard({
    required this.enabled,
    required this.onRcOff,
    required this.onRefresh,
    required this.onPidPoll,
    required this.onPidReset,
  });

  final bool enabled;
  final VoidCallback onRcOff;
  final VoidCallback onRefresh;
  final VoidCallback onPidPoll;
  final VoidCallback onPidReset;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'ADVANCED',
      subtitle: 'Safety + read gains from FC (serial)',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ActionChip(
            label: 'RC OFF',
            enabled: enabled,
            onTap: onRcOff,
          ),
          _ActionChip(
            label: 'REFRESH LIVE',
            enabled: enabled,
            onTap: onRefresh,
          ),
          _ActionChip(
            label: 'PID POLL',
            enabled: enabled,
            onTap: onPidPoll,
          ),
          _ActionChip(
            label: 'RESET ∫',
            enabled: enabled,
            onTap: onPidReset,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Material(
      color: c.cardInset,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: c.border),
          ),
          child: Text(
            label,
            style: c.labelStyle(fontSize: 8, color: enabled ? c.accent : c.label),
          ),
        ),
      ),
    );
  }
}

class _BenchDefaultsHelp extends StatelessWidget {
  const _BenchDefaultsHelp({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'WHY SOME VALUES ARE NOT ZERO',
                    style: c.labelStyle(fontSize: 9, color: c.accent, letterSpacing: 1.5),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: c.accent,
                    size: 18,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 8),
                Text(
                  'PID sliders: firmware RAM defaults (Kp/Kd ≠ 0 is correct). '
                  'Ki=0 on rate loop is normal. Gains are lost on reboot — use Load defaults.\n\n'
                  'Live panel: only ARMED|/DISARMED| serial lines. attR/attP = attitude; '
                  'rate R/P/Y = gyro deg/s (not angles). PID r/p/y = rate PID output (deg/s).\n\n'
                  'Bench: disarm → armmax 2000 → arm → stabilize on → throttle 20–45.\n'
                  'PID POLL reads pid show into sliders.',
                  style: c.labelStyle(fontSize: 8, color: c.body).copyWith(height: 1.45),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TelCell extends StatelessWidget {
  const _TelCell(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return SizedBox(
      width: 72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: c.labelStyle(fontSize: 7)),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: c.value,
            ),
          ),
        ],
      ),
    );
  }
}

class _MotorBar extends StatelessWidget {
  const _MotorBar({required this.label, required this.pct});

  final String label;
  final int pct;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final f = (pct.clamp(0, 100) / 100).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: c.labelStyle(fontSize: 7)),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: f,
            minHeight: 8,
            backgroundColor: c.track,
            color: c.accent,
          ),
        ),
        Text('$pct%', style: c.labelStyle(fontSize: 7)),
      ],
    );
  }
}

class _PidToolbar extends StatelessWidget {
  const _PidToolbar({
    required this.enabled,
    required this.busy,
    required this.onReset,
    required this.onPoll,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onReset;
  final VoidCallback onPoll;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: enabled && !busy ? onPoll : null,
          child: Text('Poll', style: TextStyle(color: c.accent, fontSize: 10)),
        ),
        TextButton(
          onPressed: enabled && !busy ? onReset : null,
          child: Text('Reset I', style: TextStyle(color: c.accent, fontSize: 10)),
        ),
      ],
    );
  }
}

class _BenchHelp extends StatelessWidget {
  const _BenchHelp({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'BENCH TUNING ORDER',
                    style: c.labelStyle(fontSize: 9, color: c.accent, letterSpacing: 2),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: c.accent,
                    size: 18,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 8),
                Text(
                  '1. disarm → armmax 2000 → arm → stabilize on → throttle 20–45\n'
                  '2. Tune rate roll/pitch (rig tied; watch PID r/p/y and motors)\n'
                  '3. Tune attitude roll/pitch\n'
                  '4. Tune yaw rate\n'
                  '5. With props: notch at motor buzz Hz\n\n'
                  'Only rc runs 20–50 Hz on Control tab. PID/filter ≤10 Hz here.',
                  style: c.labelStyle(fontSize: 8, color: c.body).copyWith(height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectBanner extends StatelessWidget {
  const _ConnectBanner();

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Enable Live ESP on Home to send tuning commands.',
        style: c.labelStyle(fontSize: 9, color: c.body).copyWith(height: 1.4),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: c.labelStyle(fontSize: 9, color: c.accent, letterSpacing: 2),
                  ),
                ),
                ?trailing,
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: c.labelStyle(fontSize: 8, color: c.body).copyWith(height: 1.3),
              ),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _LastSentLine extends StatelessWidget {
  const _LastSentLine({this.cmd, this.error});

  final String? cmd;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    if (error != null) {
      return Text(
        'Last send failed: $error',
        style: c.labelStyle(fontSize: 7, color: c.disarm),
      );
    }
    if (cmd == null) return const SizedBox.shrink();
    return Text(
      'Last sent: $cmd',
      style: c.labelStyle(fontSize: 7).copyWith(
        fontFamily: 'monospace',
        color: c.arm,
      ),
    );
  }
}

class _ThrottleRow extends StatelessWidget {
  const _ThrottleRow({
    required this.label,
    required this.enabled,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.onChanged,
    required this.onCommit,
    this.subtitle,
    this.buttonsOnly = false,
    this.step = 1,
  });

  final String label;
  final String? subtitle;
  final bool buttonsOnly;
  final bool enabled;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final double step;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommit;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: c.labelStyle(fontSize: 8)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: c.labelStyle(fontSize: 7, color: c.body)),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                '${value.round()}$unit',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: c.value,
                ),
              ),
            ),
            _IconBtn(
              enabled: enabled,
              icon: Icons.remove,
              onTap: () {
                final v = (value - step).clamp(min, max);
                onChanged(v);
                onCommit(v);
              },
            ),
            const SizedBox(width: 4),
            _IconBtn(
              enabled: enabled,
              icon: Icons.add,
              onTap: () {
                final v = (value + step).clamp(min, max);
                onChanged(v);
                onCommit(v);
              },
            ),
          ],
        ),
        IgnorePointer(
          ignoring: buttonsOnly,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: enabled && !buttonsOnly ? onChanged : null,
            onChangeEnd: enabled && !buttonsOnly ? onCommit : null,
          ),
        ),
      ],
    );
  }
}

class _PidAxisCard extends StatelessWidget {
  const _PidAxisCard({
    required this.title,
    required this.commandPreview,
    required this.enabled,
    required this.values,
    required this.onChanged,
    required this.onApply,
    required this.onReset,
  });

  final String title;
  final String commandPreview;
  final bool enabled;
  final _PidTriple values;
  final VoidCallback onChanged;
  final VoidCallback onApply;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.cardInset,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.border.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: c.labelStyle(color: c.accent),
                  ),
                ),
                TextButton(
                  onPressed: enabled ? onApply : null,
                  child: Text('Apply', style: TextStyle(color: c.accent, fontSize: 10)),
                ),
              ],
            ),
            Text(
              commandPreview,
              style: c.labelStyle(fontSize: 7).copyWith(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 6),
            _PidTermRow(
              label: 'Kp',
              enabled: enabled,
              value: values.kp,
              min: 0,
              max: 10,
              step: 0.001,
              decimals: 3,
              onChanged: (v) {
                values.kp = v;
                onChanged();
              },
              onCommit: onApply,
            ),
            const SizedBox(height: 6),
            _PidTermRow(
              label: 'Ki',
              enabled: enabled,
              value: values.ki,
              min: 0,
              max: 2,
              step: 0.001,
              decimals: 3,
              onChanged: (v) {
                values.ki = v;
                onChanged();
              },
              onCommit: onApply,
            ),
            const SizedBox(height: 6),
            _PidTermRow(
              label: 'Kd',
              enabled: enabled,
              value: values.kd,
              min: 0,
              max: 0.05,
              step: 0.0005,
              decimals: 4,
              onChanged: (v) {
                values.kd = v;
                onChanged();
              },
              onCommit: onApply,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: enabled ? onReset : null,
                child: Text('Defaults', style: TextStyle(color: c.label, fontSize: 9)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PidTermRow extends StatelessWidget {
  const _PidTermRow({
    required this.label,
    required this.enabled,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.decimals,
    required this.onChanged,
    required this.onCommit,
  });

  final String label;
  final bool enabled;
  final double value;
  final double min;
  final double max;
  final double step;
  final int decimals;
  final ValueChanged<double> onChanged;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: c.labelStyle(fontSize: 7)),
        const SizedBox(height: 2),
        _ParamSliderRow(
          enabled: enabled,
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) / step).round().clamp(10, 400),
          display: value.toStringAsFixed(decimals),
          step: step,
          onChanged: onChanged,
          onCommit: (_) => onCommit(),
          onReset: () {},
        ),
      ],
    );
  }
}

class _ParamSliderRow extends StatelessWidget {
  const _ParamSliderRow({
    required this.enabled,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.step,
    required this.onChanged,
    required this.onCommit,
    required this.onReset,
  });

  final bool enabled;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final double step;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: enabled
                ? (v) {
                    HapticFeedback.selectionClick();
                    onChanged(v);
                  }
                : null,
            onChangeEnd: enabled ? onCommit : null,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: c.value,
            ),
          ),
        ),
        _IconBtn(
          enabled: enabled,
          icon: Icons.remove,
          onTap: () {
            final v = (value - step).clamp(min, max);
            onChanged(v);
            onCommit(v);
          },
        ),
        _IconBtn(
          enabled: enabled,
          icon: Icons.add,
          onTap: () {
            final v = (value + step).clamp(min, max);
            onChanged(v);
            onCommit(v);
          },
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.enabled,
    required this.icon,
    required this.onTap,
  });

  final bool enabled;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Material(
      color: c.iconButtonBg,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 16, color: c.accent),
        ),
      ),
    );
  }
}
