import 'package:flutter/material.dart';

import 'widgets/app_motion.dart';

/// High-contrast theme for the calibration flow.
abstract final class CalTheme {
  static const bg = Color(0xFF2A2E34);
  static const card = Color(0xFF353B44);
  static const cardBorder = Color(0xFF5A6470);
  static const text = Color(0xFFE8E4DC);
  static const textDim = Color(0xFFB8B0A4);
  static const accent = Color(0xFFE8941A);
  static const danger = Color(0xFFE85A4A);
  static const success = Color(0xFF3DD66E);
  static const stepDot = Color(0xFF6A7480);
  static const stepActive = Color(0xFFE8941A);

  static TextStyle get title => const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
        color: accent,
      );

  static TextStyle get stepTitle => const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: text,
        height: 1.25,
      );

  static TextStyle get body => const TextStyle(
        fontSize: 15,
        height: 1.5,
        color: text,
      );

  static TextStyle get hint => const TextStyle(
        fontSize: 13,
        height: 1.4,
        color: textDim,
      );
}

enum _CalFlow { esc, imu }

class _WizardStep {
  const _WizardStep({
    required this.title,
    required this.body,
    this.showDisarm = false,
  });

  final String title;
  final String body;
  final bool showDisarm;
}

class CalibrationPage extends StatelessWidget {
  const CalibrationPage({
    super.key,
    required this.useEsp,
    required this.busy,
    required this.onRunCommand,
    required this.onDisarm,
    required this.onConnect,
    required this.sendCalCommand,
  });

  final bool useEsp;
  final bool busy;
  final Future<bool> Function(String label, Future<String> Function() fn) onRunCommand;
  final VoidCallback onDisarm;
  final Future<bool> Function() onConnect;
  final Future<String> Function(String cmd) sendCalCommand;

  Future<void> _openWizard(BuildContext context, _CalFlow flow) async {
    if (busy) return;
    var canRun = useEsp;
    if (!canRun) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: CalTheme.card,
          title: const Text('Connect first?', style: TextStyle(color: CalTheme.accent)),
          content: Text(
            'Live ESP is off. Connect to the drone Wi‑Fi, then tap Connect to ESP.',
            style: CalTheme.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: CalTheme.accent),
              child: const Text('CONNECT', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
      if (go != true || !context.mounted) return;
      canRun = await onConnect();
      if (!canRun || !context.mounted) return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _CalWizardPage(
          flow: flow,
          busy: busy,
          onRunCommand: onRunCommand,
          onDisarm: onDisarm,
          sendCalCommand: sendCalCommand,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CalTheme.bg,
      body: SafeArea(
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('CALIBRATION', style: CalTheme.title, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Tap a procedure below. Steps appear one at a time; cal runs at the end.',
                  style: CalTheme.hint,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _ConnectionBanner(
                  useEsp: useEsp,
                  busy: busy,
                  onConnect: onConnect,
                ),
                const SizedBox(height: 20),
                StaggeredFadeIn(
                  index: 0,
                  child: _MainCalButton(
                    title: 'ESC Calibration',
                    subtitle: 'SimonK · all 4 motors · ~12 s',
                    icon: Icons.settings_input_component_rounded,
                    busy: busy,
                    onTap: () => _openWizard(context, _CalFlow.esc),
                  ),
                ),
                const SizedBox(height: 14),
                StaggeredFadeIn(
                  index: 1,
                  child: _MainCalButton(
                    title: 'IMU Calibration',
                    subtitle: 'Gyro + accel · board still · ~3 s',
                    icon: Icons.compass_calibration_rounded,
                    busy: busy,
                    onTap: () => _openWizard(context, _CalFlow.imu),
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: 20),
                  const LinearProgressIndicator(
                    color: CalTheme.accent,
                    backgroundColor: CalTheme.card,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.useEsp,
    required this.busy,
    required this.onConnect,
  });

  final bool useEsp;
  final bool busy;
  final Future<bool> Function() onConnect;

  @override
  Widget build(BuildContext context) {
    if (useEsp) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CalTheme.success.withValues(alpha: 0.15),
          border: Border.all(color: CalTheme.success, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_rounded, color: CalTheme.success, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Live ESP is ON',
                style: CalTheme.body.copyWith(
                  color: CalTheme.success,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CalTheme.danger.withValues(alpha: 0.12),
        border: Border.all(color: CalTheme.danger, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Live ESP is OFF',
            style: CalTheme.stepTitle.copyWith(color: CalTheme.danger, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Join drone Wi‑Fi, then connect:',
            style: CalTheme.body,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: busy ? null : onConnect,
              icon: const Icon(Icons.link_rounded),
              label: const Text('CONNECT TO ESP'),
              style: FilledButton.styleFrom(
                backgroundColor: CalTheme.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MainCalButton extends StatelessWidget {
  const _MainCalButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 88,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: CalTheme.card,
          foregroundColor: CalTheme.text,
          disabledBackgroundColor: CalTheme.card.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: CalTheme.accent, width: 2),
          ),
          elevation: 4,
        ),
        child: Row(
          children: [
            Icon(icon, size: 36, color: CalTheme.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: CalTheme.stepTitle),
                  Text(subtitle, style: CalTheme.hint),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 32, color: CalTheme.accent),
          ],
        ),
      ),
    );
  }
}

class _CalWizardPage extends StatefulWidget {
  const _CalWizardPage({
    required this.flow,
    required this.busy,
    required this.onRunCommand,
    required this.onDisarm,
    required this.sendCalCommand,
  });

  final _CalFlow flow;
  final bool busy;
  final Future<bool> Function(String label, Future<String> Function() fn) onRunCommand;
  final VoidCallback onDisarm;
  final Future<String> Function(String cmd) sendCalCommand;

  @override
  State<_CalWizardPage> createState() => _CalWizardPageState();
}

class _CalWizardPageState extends State<_CalWizardPage> {
  int _step = 0;
  bool _running = false;

  List<_WizardStep> get _steps {
    switch (widget.flow) {
      case _CalFlow.esc:
        return const [
          _WizardStep(
            title: 'Before you start',
            body:
                'Remove all propellers. Arm is blocked during calibration. '
                'Do not send other commands for about 12 seconds once calibration starts.',
          ),
          _WizardStep(
            title: 'ESC power off',
            body: 'Disconnect the ESC battery now. Props must stay off.',
          ),
          _WizardStep(
            title: 'What happens next',
            body:
                'MAX throttle (2000 µs) on M1–M4 for 2 s, then you connect the ESC battery.',
          ),
          _WizardStep(
            title: 'Connect battery when asked',
            body: 'Wait ~5 s after connecting. Listen for ESC beep tones.',
          ),
          _WizardStep(
            title: 'Minimum throttle phase',
            body: 'MIN throttle (1000 µs) on all four motors for 5 seconds.',
          ),
          _WizardStep(
            title: 'Finish',
            body: 'Wait for OK ESC cal DONE and a short beep on the board.',
          ),
        ];
      case _CalFlow.imu:
        return const [
          _WizardStep(
            title: 'Disarm first',
            body: 'Drone must be disarmed. Tap Disarm if needed.',
            showDisarm: true,
          ),
          _WizardStep(
            title: 'Position the board',
            body: 'Place the board flat and still on a desk.',
          ),
          _WizardStep(
            title: 'Calibration duration',
            body: 'About 3 seconds. Do not move the board.',
          ),
        ];
    }
  }

  bool get _onRunScreen => _step >= _steps.length;
  bool get _isBusy => widget.busy || _running;

  Future<void> _startCalibration() async {
    setState(() => _running = true);
    final ok = await widget.onRunCommand(
      widget.flow == _CalFlow.esc ? 'ESC Calibration' : 'IMU Calibration',
      () => widget.sendCalCommand(
        widget.flow == _CalFlow.esc ? 'calibrate' : 'cal imu',
      ),
    );
    if (mounted) {
      setState(() => _running = false);
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _steps.length;
    final onRun = _onRunScreen;

    return Scaffold(
      backgroundColor: CalTheme.bg,
      appBar: AppBar(
        backgroundColor: CalTheme.card,
        foregroundColor: CalTheme.text,
        title: Text(widget.flow == _CalFlow.esc ? 'ESC Cal' : 'IMU Cal'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isBusy ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!onRun) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: List.generate(total, (i) {
                    return Expanded(
                      child: AnimatedContainer(
                        duration: AppMotion.mediumMs,
                        curve: Curves.easeOutCubic,
                        height: 5,
                        margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
                        decoration: BoxDecoration(
                          color: i <= _step ? CalTheme.stepActive : CalTheme.stepDot,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: i == _step
                              ? [
                                  BoxShadow(
                                    color: CalTheme.stepActive.withValues(alpha: 0.5),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Step ${_step + 1} of $total',
                  style: CalTheme.hint.copyWith(color: CalTheme.accent),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: AnimatedWizardStep(
                  stepKey: onRun ? 'run' : _step,
                  child: onRun
                      ? Column(
                          children: [
                            const BounceIn(
                              child: Icon(
                                Icons.play_circle_fill,
                                size: 64,
                                color: CalTheme.accent,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Ready to calibrate',
                              style: CalTheme.stepTitle,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.flow == _CalFlow.esc
                                  ? 'Sends "calibrate" (~12 s). Watch serial for progress.'
                                  : 'Sends "cal imu" (~3 s). Keep board still.',
                              style: CalTheme.body,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_steps[_step].title, style: CalTheme.stepTitle),
                            const SizedBox(height: 16),
                            Text(_steps[_step].body, style: CalTheme.body),
                          ],
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (onRun)
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _isBusy ? null : _startCalibration,
                        style: FilledButton.styleFrom(
                          backgroundColor: CalTheme.accent,
                          foregroundColor: Colors.black,
                        ),
                        child: _running
                            ? const CircularProgressIndicator(color: Colors.black)
                            : Text(
                                widget.flow == _CalFlow.esc
                                    ? 'START ESC CALIBRATION'
                                    : 'START IMU CALIBRATION',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    )
                  else ...[
                    if (_steps[_step].showDisarm) ...[
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _isBusy ? null : widget.onDisarm,
                          icon: const Icon(Icons.lock_rounded),
                          label: const Text('DISARM NOW'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: CalTheme.danger,
                            side: const BorderSide(color: CalTheme.danger, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _isBusy ? null : () => setState(() => _step++),
                        style: FilledButton.styleFrom(
                          backgroundColor: CalTheme.accent,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text(
                          'CONTINUE',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                    ),
                    if (_step > 0)
                      TextButton(
                        onPressed: _isBusy ? null : () => setState(() => _step--),
                        child: const Text('Back'),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
