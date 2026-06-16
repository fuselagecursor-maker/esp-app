import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_toast.dart';
import 'calibration_page.dart';
import 'fc_tune_commands.dart';
import 'fc_tune_page.dart';
import 'map_page.dart';
import 'serial_monitor_page.dart';
import 'stm32_reply.dart';
import 'control_page.dart';
import 'manual_control_page.dart';
import 'kill_page.dart';
import 'attitude_3d_page.dart';
import 'drone_http_client.dart';
import 'led_backend.dart';
import 'responsive_layout.dart';
import 'serial_log_cache.dart';
import 'widgets/app_motion.dart';
import 'widgets/app_side_rail.dart';
import 'widgets/global_kill_button.dart';
import 'widgets/tx_hold_to_arm.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const LedRemoteApp());
}

class LedRemoteApp extends StatelessWidget {
  const LedRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0D9488),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Drone Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: scheme.surfaceContainerLowest,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      home: const RemoteShell(),
    );
  }
}

class RemoteShell extends StatefulWidget {
  const RemoteShell({super.key});

  @override
  State<RemoteShell> createState() => _RemoteShellState();
}

/// Shared connection + drone client for Home and Control tabs.
class RemoteSession {
  RemoteSession._(this._shell);

  final _RemoteShellState _shell;

  bool get useEsp => _shell._useEsp;
  bool get busy => _shell._busy;
  bool get ledOn => _shell._ledOn;
  TextEditingController get urlController => _shell._urlController;
  TextEditingController get customCommandController => _shell._customCommandController;
  DroneHttpClient get drone => _shell._drone;

  Future<void> setUseEsp(bool value) => _shell.setUseEsp(value);
  Future<void> testConnection() => _shell.testConnection();
  Future<bool> connectEsp() => _shell.connectEsp();
  Future<void> toggleLed() => _shell.toggleLed();
  Future<void> syncLed() => _shell.syncLed();
  Future<void> droneAction(String label, Future<String> Function() fn) =>
      _shell.droneAction(label, fn);
  Future<void> sendTuneCommand(String label, String cmd) =>
      _shell.sendTuneCommand(label, cmd);
  Future<void> sendCustomLine() => _shell.sendCustomLine();
  void insertCommand(String cmd) => _shell.insertCommand(cmd);
  void notify(String msg, {bool isError = true}) => _shell.toast(msg, isError: isError);
  bool get armBusy => _shell._armBusy;
  bool get appArmed => _shell._appArmed;
  int get reportedThrottlePct => _shell._reportedThrottlePct;
  Future<bool> armFlight({int? throttlePercent}) =>
      _shell.armFlight(throttlePercent: throttlePercent);
  Future<bool> disarmFlight() => _shell.disarmFlight();
  void killFlight() => _shell.killFlight();
  DateTime? get lastKillAt => _shell._lastKillAt;
  void reportThrottlePercent(int pct) => _shell.reportThrottlePercent(pct);
  Future<bool> calAction(String label, Future<String> Function() fn) =>
      _shell.calAction(label, fn);
  Future<String> sendCalCommand(String cmd) => _shell.sendCalCommand(cmd);
  Future<List<String>> fetchStm32Serial() => _shell.fetchStm32Serial();
  SerialLogCache get serialCache => _shell._serialCache;
  Future<void> clearStm32Serial() => _shell.clearStm32Serial();
}

class RemoteScope extends InheritedWidget {
  const RemoteScope({
    super.key,
    required this.session,
    required super.child,
  });

  final RemoteSession session;

  static RemoteSession of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RemoteScope>();
    assert(scope != null, 'RemoteScope not found');
    return scope!.session;
  }

  @override
  bool updateShouldNotify(RemoteScope oldWidget) {
    return session.useEsp != oldWidget.session.useEsp ||
        session.busy != oldWidget.session.busy ||
        session.ledOn != oldWidget.session.ledOn ||
        session.armBusy != oldWidget.session.armBusy ||
        session.appArmed != oldWidget.session.appArmed ||
        session.reportedThrottlePct != oldWidget.session.reportedThrottlePct;
  }
}

class _RemoteShellState extends State<RemoteShell> with WidgetsBindingObserver {
  int _tab = 0;
  DateTime? _lastKillAt;

  final _mock = MockLedBackend();
  final _urlController = TextEditingController(text: 'http://192.168.4.1');
  final _customCommandController = TextEditingController();
  late final EspHttpLedBackend _httpBackend = EspHttpLedBackend(_urlController.text);
  late final DroneHttpClient _drone = DroneHttpClient(_urlController.text);
  late final SerialLogCache _serialCache = SerialLogCache(
    fetchFromDrone: () {
      _drone.setBaseUrl(_urlController.text);
      return _drone.fetchStm32SerialLog();
    },
  );

  bool _useEsp = false;
  bool _ledOn = false;
  bool _busy = false;
  bool _armBusy = false;
  bool _appArmed = false;
  int _reportedThrottlePct = 0;

  LedBackend get _backend => _useEsp ? _httpBackend : _mock;

  void reportThrottlePercent(int pct) {
    _reportedThrottlePct = pct.clamp(0, 100);
  }

  static bool _isArmCommand(String raw) {
    final l = raw.trim().toLowerCase();
    return l == 'arm' || l == 'test arm';
  }

  bool _throttleBlocksArm() =>
      !ControlPage.throttleAllowsArm(_reportedThrottlePct);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serialCache.dispose();
    _drone.close();
    _urlController.dispose();
    _customCommandController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Safety: if the app loses focus / goes background, immediately stop RC + disarm.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      setState(() => _appArmed = false);
      _disarmInBackground();
    }
  }

  void toast(String msg, {bool isError = true}) {
    if (!mounted) return;
    AppToast.show(context, msg, isError: isError, isSuccess: !isError);
  }

  Future<void> toggleLed() async {
    setState(() => _busy = true);
    try {
      if (_useEsp) _httpBackend.setBaseUrl(_urlController.text);
      final on = await _backend.toggle();
      setState(() => _ledOn = on);
    } catch (e) {
      toast('LED: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> syncLed() async {
    if (!_useEsp) return;
    setState(() => _busy = true);
    try {
      _httpBackend.setBaseUrl(_urlController.text);
      final on = await _httpBackend.readState();
      setState(() => _ledOn = on);
    } catch (e) {
      toast('Sync failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> sendCalCommand(String cmd) {
    _drone.setBaseUrl(_urlController.text);
    final lower = cmd.trim().toLowerCase();
    if (lower == 'cal help') {
      return _drone.sendCommandLine('cal help');
    }
    return _drone.sendCalibrationCommand(cmd);
  }

  Future<List<String>> fetchStm32Serial() => _serialCache.getLines();

  Future<void> clearStm32Serial() async {
    _drone.setBaseUrl(_urlController.text);
    await _drone.clearStm32SerialLog();
  }

  Future<bool> calAction(String label, Future<String> Function() fn) async {
    if (!_useEsp) {
      toast('Enable “Live ESP” and join the drone Wi‑Fi first.');
      return false;
    }
    final esc = label.toLowerCase().contains('esc');
    setState(() => _busy = true);
    try {
      _drone.setBaseUrl(_urlController.text);
      final reply = await fn();

      if (Stm32Reply.espFailed(reply)) {
        toast('$label failed: $reply');
        return false;
      }
      if (Stm32Reply.calComplete(reply, esc: esc)) {
        final stm = Stm32Reply.stm32Text(reply);
        toast(
          stm != null ? '$label finished.\n$stm' : '$label finished.',
          isError: false,
        );
        return true;
      }
      if (Stm32Reply.noStm32Reply(reply)) {
        toast(
          '$label: no reply on ESP↔STM32 UART. '
          'Command may not reach STM32 USB serial — enable LPUART1 (PB6/PB7).',
        );
        return false;
      }
      final stm = Stm32Reply.stm32Text(reply);
      toast(
        stm != null
            ? '$label: STM32 did not send DONE yet.\n$stm'
            : '$label: timed out waiting for calibration DONE from STM32.',
      );
      return false;
    } catch (e) {
      toast('$label: $e');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> droneAction(String label, Future<String> Function() fn) async {
    if (!_useEsp) {
      toast('Enable “Live ESP” and join the drone Wi‑Fi first.');
      return;
    }
    setState(() => _busy = true);
    try {
      _drone.setBaseUrl(_urlController.text);
      final reply = await fn();
      if (reply.contains('"ok":false')) {
        toast('$label failed: $reply');
      } else if (reply.contains('no_stm32_reply')) {
        toast(
          '$label sent on UART — STM32 did not answer. '
          'Enable LPUART1 (PB6/PB7) in STM32 firmware or check wiring.',
        );
      } else if (!Stm32Reply.commandAccepted(reply)) {
        toast('$label: STM32 did not confirm — check Serial tab.');
      } else {
        toast('$label OK', isError: false);
      }
    } catch (e) {
      toast('$label: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tune tab: no global [ _busy ] lock; throttle uses ESP live-forward path.
  Future<void> sendTuneCommand(String label, String cmd) async {
    if (!_useEsp) {
      toast('Enable Live ESP on Home first.');
      return;
    }
    _drone.setBaseUrl(_urlController.text);
    final line = cmd.trim();
    if (line.isEmpty) return;

    try {
      final lower = line.toLowerCase();
      final useLive = lower.startsWith('throttle ') || lower == 'rc off';

      if (useLive) {
        await _drone.sendCommandLive(line);
        return;
      }

      if (line.length > FcTuneCommands.maxLineLength) {
        toast('$label: line too long for ESP (${line.length} > ${FcTuneCommands.maxLineLength})');
        return;
      }

      final reply = await _drone.sendCommandLine(line);
      if (Stm32Reply.espFailed(reply)) {
        toast('$label failed — check Serial tab');
        return;
      }
      if (Stm32Reply.noStm32Reply(reply)) {
        toast('$label sent — no STM32 reply on UART');
        return;
      }
      if (!Stm32Reply.tuneCommandOk(reply)) {
        final hint = Stm32Reply.stm32Text(reply);
        toast(
          hint != null ? '$label: $hint' : '$label: unexpected reply — Serial tab',
        );
      }
    } catch (e) {
      toast('$label: $e');
    }
  }

  Future<void> sendCustomLine() async {
    final raw = _customCommandController.text.trim();
    if (raw.isEmpty) {
      toast('Enter a command first.');
      return;
    }
    if (_isArmCommand(raw) && _throttleBlocksArm()) {
      toast(ControlPage.throttleArmBlockMessage(_reportedThrottlePct));
      return;
    }
    await droneAction('Send', () => _drone.sendCommandLine(raw));
  }

  void insertCommand(String cmd) {
    final t = _customCommandController.text;
    _customCommandController.text = t.isEmpty ? cmd : '$t\n$cmd';
    _customCommandController.selection = TextSelection.collapsed(
      offset: _customCommandController.text.length,
    );
  }

  Future<void> setUseEsp(bool value) async {
    if (value == _useEsp) return;
    if (!value) {
      _serialCache.setActive(false);
      final on = await _mock.readState();
      if (mounted) {
        setState(() {
          _useEsp = false;
          _ledOn = on;
          _appArmed = false;
        });
      }
      return;
    }
    setState(() {
      _useEsp = true;
      _ledOn = false;
    });
    // Defer first serial poll so the toggle and sidebar stay responsive.
    scheduleMicrotask(() {
      if (mounted && _useEsp) _serialCache.setActive(true);
    });
  }

  Future<bool> armFlight({int? throttlePercent}) async {
    final thr = (throttlePercent ?? _reportedThrottlePct).clamp(0, 100);
    if (!ControlPage.throttleAllowsArm(thr)) {
      toast(ControlPage.throttleArmBlockMessage(thr));
      return false;
    }
    final ok = await _flightSwitch('Arm', _drone.arm);
    if (ok && mounted) {
      setState(() {
        _appArmed = true;
        _reportedThrottlePct = thr;
      });
      _drone.setBaseUrl(_urlController.text);
      final postThr = throttlePercent != null ? thr : 0;
      unawaited(_drone.sendCommandLive('throttle $postThr'));
      unawaited(_drone.sendCommandLive('rc 0 0 0 0'));
    }
    return ok;
  }

  Future<bool> disarmFlight() async {
    final ok = await _flightSwitch('Disarm', _drone.disarm);
    if (ok && mounted) setState(() => _appArmed = false);
    return ok;
  }

  void killFlight() {
    setState(() {
      _appArmed = false;
      _reportedThrottlePct = 0;
      _lastKillAt = DateTime.now();
    });
    if (_useEsp) {
      _drone.setBaseUrl(_urlController.text);
      _drone.sendKillInstant();
    }
    toast(
      _useEsp ? 'KILL sent — rc off, throttle 0, disarm' : 'KILL — app disarmed (Live ESP off)',
      isError: false,
    );
  }

  /// Best-effort safety stop without blocking the UI (app background).
  void _disarmInBackground() {
    if (!_useEsp) return;
    _drone.setBaseUrl(_urlController.text);
    _drone.sendKillInstant();
  }

  void _switchTab(int next) {
    if (next == _tab) return;
    setState(() => _tab = next);
  }

  Future<bool> _flightSwitch(String label, Future<String> Function() fn) async {
    if (!_useEsp) {
      toast('Enable “Live ESP” and join the drone Wi‑Fi first.');
      return false;
    }
    setState(() => _armBusy = true);
    try {
      _drone.setBaseUrl(_urlController.text);
      final reply = await fn();
      if (Stm32Reply.espFailed(reply)) {
        toast('$label failed: $reply');
        return false;
      }
      if (Stm32Reply.noStm32Reply(reply)) {
        toast('$label sent — no STM32 reply on UART.');
        return false;
      }
      if (!Stm32Reply.commandAccepted(reply)) {
        toast('$label: STM32 did not confirm.');
        return false;
      }
      return true;
    } catch (e) {
      toast('$label: $e');
      return false;
    } finally {
      if (mounted) setState(() => _armBusy = false);
    }
  }

  Future<void> testConnection() async {
    _httpBackend.setBaseUrl(_urlController.text);
    _drone.setBaseUrl(_urlController.text);
    setState(() => _busy = true);
    try {
      final on = await _httpBackend.readState();
      if (mounted) {
        setState(() => _ledOn = on);
        toast('Connected to ESP', isError: false);
      }
    } catch (e) {
      toast('Connection failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ping ESP and turn on Live ESP mode (for Cal / Control tabs).
  Future<bool> connectEsp() async {
    _httpBackend.setBaseUrl(_urlController.text);
    _drone.setBaseUrl(_urlController.text);
    setState(() => _busy = true);
    try {
      final on = await _httpBackend.readState();
      if (mounted) {
        setState(() {
          _useEsp = true;
          _ledOn = on;
        });
        _serialCache.setActive(true);
        toast('Live ESP enabled — connected.', isError: false);
        return true;
      }
      return false;
    } catch (e) {
      toast('Connection failed: $e');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  late final RemoteSession _session = RemoteSession._(this);

  @override
  Widget build(BuildContext context) {
    final landscape = isLandscape(context);
    final Widget body = AppTabTransition(
      child: switch (_tab) {
        0 => LedRemotePage(key: ValueKey('home-$_useEsp-$_ledOn')),
        1 => const ControlTabPage(key: ValueKey('tab-control')),
        2 => const ManualControlTabPage(key: ValueKey('tab-manual')),
        3 => const CalibrationTabPage(key: ValueKey('tab-cal')),
        4 => const FcTuneTabPage(key: ValueKey('tab-tune')),
        5 => const MapTabPage(key: ValueKey('tab-map')),
        6 => const SerialMonitorTabPage(key: ValueKey('tab-serial')),
        7 => const KillTabPage(key: ValueKey('tab-kill')),
        8 => const AttitudeTabPage(key: ValueKey('tab-3d')),
        _ => LedRemotePage(key: ValueKey('home-$_useEsp-$_ledOn')),
      },
    );

    return RemoteScope(
      session: _session,
      child: landscape
          ? Scaffold(
              backgroundColor: const Color(0xFF202326),
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSideRail(
                    selectedIndex: _tab,
                    onDestinationSelected: _switchTab,
                    showKill: true,
                    onKill: killFlight,
                  ),
                  Expanded(child: body),
                ],
              ),
            )
          : Scaffold(
              backgroundColor: _tab == 3
                  ? const Color(0xFF2A2E34)
                  : (_tab >= 1 ? const Color(0xFF202326) : null),
              body: body,
              bottomNavigationBar: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: const Color(0xFF141618),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                        child: GlobalKillButton(
                          fullWidth: true,
                          onKill: killFlight,
                        ),
                      ),
                    ),
                  ),
                  NavigationBar(
                    backgroundColor: _tab >= 1
                        ? const Color(0xFF282C30)
                        : null,
                    indicatorColor: const Color(0xFFC07010),
                    selectedIndex: _tab,
                    onDestinationSelected: _switchTab,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.sports_esports_outlined),
                        selectedIcon: Icon(Icons.sports_esports_rounded),
                        label: 'Control',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.slideshow_outlined),
                        selectedIcon: Icon(Icons.slideshow_rounded),
                        label: 'Manual',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.tune_outlined),
                        selectedIcon: Icon(Icons.tune_rounded),
                        label: 'Cal',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_suggest_outlined),
                        selectedIcon: Icon(Icons.settings_suggest_rounded),
                        label: 'Tune',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.map_outlined),
                        selectedIcon: Icon(Icons.map_rounded),
                        label: 'Map',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.terminal_outlined),
                        selectedIcon: Icon(Icons.terminal_rounded),
                        label: 'Serial',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.emergency_share_outlined, color: Color(0xFFEF4444)),
                        selectedIcon: Icon(Icons.emergency_share_rounded, color: Color(0xFFEF4444)),
                        label: 'E-Stop',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.view_in_ar_outlined),
                        selectedIcon: Icon(Icons.view_in_ar_rounded),
                        label: '3D',
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class MapTabPage extends StatelessWidget {
  const MapTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = RemoteScope.of(context);
    return MapPage(
      useEsp: session.useEsp,
      fetchSerial: session.useEsp ? session.fetchStm32Serial : null,
    );
  }
}

class FcTuneTabPage extends StatelessWidget {
  const FcTuneTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = RemoteScope.of(context);
    return FcTunePage(
      useEsp: session.useEsp,
      armed: session.appArmed,
      busy: session.busy,
      armBusy: session.armBusy,
      serialCache: session.serialCache,
      onNotify: session.notify,
      onThrottleReport: session.reportThrottlePercent,
      onSendCommand: session.sendTuneCommand,
      onArm: (thr) => session.armFlight(throttlePercent: thr),
      onDisarm: session.disarmFlight,
      customCommandController: session.customCommandController,
      onSendCustomLine: session.sendCustomLine,
      onInsertCommand: session.insertCommand,
      onClearSerialLog: session.clearStm32Serial,
    );
  }
}

class CalibrationTabPage extends StatelessWidget {
  const CalibrationTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = RemoteScope.of(context);
    return CalibrationPage(
      useEsp: session.useEsp,
      busy: session.busy,
      onRunCommand: session.calAction,
      onDisarm: session.disarmFlight,
      onConnect: session.connectEsp,
      sendCalCommand: session.sendCalCommand,
    );
  }
}

class SerialMonitorTabPage extends StatelessWidget {
  const SerialMonitorTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = RemoteScope.of(context);
    return SerialMonitorPage(
      useEsp: session.useEsp,
      busy: session.busy,
      serialCache: session.serialCache,
      clearLog: session.clearStm32Serial,
      onConnect: session.connectEsp,
    );
  }
}

class KillTabPage extends StatelessWidget {
  const KillTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = RemoteScope.of(context);
    return KillPage(
      key: ValueKey('kill-${session.lastKillAt?.millisecondsSinceEpoch ?? 0}'),
      useEsp: session.useEsp,
      onKill: session.killFlight,
      lastKillAt: session.lastKillAt,
    );
  }
}

class AttitudeTabPage extends StatelessWidget {
  const AttitudeTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = RemoteScope.of(context);
    return Attitude3DPage(
      useEsp: session.useEsp,
      serialCache: session.serialCache,
      onConnect: session.connectEsp,
      onSendCommand: session.sendTuneCommand,
      commandBusy: session.busy,
    );
  }
}

class ControlTabPage extends StatelessWidget {
  const ControlTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = RemoteScope.of(context);
    return ControlPage(
      key: ValueKey('control-${session.useEsp}'),
      useEsp: session.useEsp,
      baseUrl: session.urlController.text,
      drone: session.drone,
      onNotify: session.notify,
      initialHeldThrottlePercent: session.reportedThrottlePct,
      onThrottleReport: session.reportThrottlePercent,
      fetchSerial: session.useEsp ? session.fetchStm32Serial : null,
      armBusy: session.armBusy,
      onArm: session.armFlight,
      onDisarm: session.disarmFlight,
      initialArmed: session.appArmed,
    );
  }
}

class ManualControlTabPage extends StatelessWidget {
  const ManualControlTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = RemoteScope.of(context);
    return ManualControlPage(
      key: ValueKey('manual-${session.useEsp}'),
      useEsp: session.useEsp,
      baseUrl: session.urlController.text,
      drone: session.drone,
      onNotify: session.notify,
      initialThrottlePercent: session.reportedThrottlePct,
      onThrottleReport: session.reportThrottlePercent,
      initialArmed: session.appArmed,
      onArm: session.armFlight,
      onDisarm: session.disarmFlight,
      armBusy: session.armBusy,
    );
  }
}

class LedRemotePage extends StatelessWidget {
  const LedRemotePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = RemoteScope.of(context);
    final busy = s.busy;
    final useEsp = s.useEsp;
    final ledOn = s.ledOn;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final landscape = isLandscape(context);

    return Scaffold(
      appBar: landscape
          ? null
          : AppBar(
              centerTitle: true,
              title: const Text('Drone Remote'),
              elevation: 0,
              scrolledUnderElevation: 1,
            ),
      body: SafeArea(
        child: landscape
            ? _HomeLandscapeView(
                session: s,
                busy: busy,
                useEsp: useEsp,
                ledOn: ledOn,
                theme: theme,
                cs: cs,
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _HomePortraitView(
                    session: s,
                    busy: busy,
                    useEsp: useEsp,
                    ledOn: ledOn,
                    theme: theme,
                    cs: cs,
                  ),
                ),
              ),
      ),
    );
  }
}

Future<void> _homeHoldToArm(BuildContext context, RemoteSession session) async {
  final held = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1C1F),
      title: const Text('Hold to ARM'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Press and hold until the bar fills.\n'
            'Throttle: ${session.reportedThrottlePct}%',
          ),
          const SizedBox(height: 12),
          Center(
            child: TxHoldArmChip(
              armed: false,
              busy: session.armBusy,
              onDisarm: () => Navigator.pop(ctx, false),
              onArmHoldComplete: () async => Navigator.pop(ctx, true),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (held != true || !context.mounted) return;

  final confirm = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1C1F),
      title: const Text('Confirm ARM'),
      content: Text(
        'This will ARM the drone.\n\n'
        'Throttle: ${session.reportedThrottlePct}%\n\n'
        'Confirm only if props area is clear.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('ARM'),
        ),
      ],
    ),
  );
  if (confirm == true) {
    await session.armFlight();
  }
}

class _HomePortraitView extends StatelessWidget {
  const _HomePortraitView({
    required this.session,
    required this.busy,
    required this.useEsp,
    required this.ledOn,
    required this.theme,
    required this.cs,
  });

  final RemoteSession session;
  final bool busy;
  final bool useEsp;
  final bool ledOn;
  final ThemeData theme;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: pagePadding(context),
      children: _HomeSections.buildAll(
        context: context,
        session: session,
        busy: busy,
        useEsp: useEsp,
        ledOn: ledOn,
        theme: theme,
        cs: cs,
        commandLines: 4,
        compactLed: false,
      ),
    );
  }
}

class _HomeLandscapeView extends StatelessWidget {
  const _HomeLandscapeView({
    required this.session,
    required this.busy,
    required this.useEsp,
    required this.ledOn,
    required this.theme,
    required this.cs,
  });

  final RemoteSession session;
  final bool busy;
  final bool useEsp;
  final bool ledOn;
  final ThemeData theme;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final sections = _HomeSections(
      session: session,
      busy: busy,
      useEsp: useEsp,
      ledOn: ledOn,
      theme: theme,
      cs: cs,
      commandLines: 2,
      compactLed: true,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: pad,
            children: [
              StaggeredFadeIn(index: 0, child: sections.connection()),
              const SizedBox(height: 16),
              StaggeredFadeIn(index: 1, child: sections.led()),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ListView(
            padding: pad,
            children: [
              StaggeredFadeIn(index: 2, child: sections.flight(context)),
              const SizedBox(height: 16),
              StaggeredFadeIn(index: 3, child: sections.commands()),
            ],
          ),
        ),
      ],
    );
  }
}

class _HomeSections {
  _HomeSections({
    required this.session,
    required this.busy,
    required this.useEsp,
    required this.ledOn,
    required this.theme,
    required this.cs,
    required this.commandLines,
    required this.compactLed,
  });

  final RemoteSession session;
  final bool busy;
  final bool useEsp;
  final bool ledOn;
  final ThemeData theme;
  final ColorScheme cs;
  final int commandLines;
  final bool compactLed;

  static List<Widget> buildAll({
    required BuildContext context,
    required RemoteSession session,
    required bool busy,
    required bool useEsp,
    required bool ledOn,
    required ThemeData theme,
    required ColorScheme cs,
    required int commandLines,
    required bool compactLed,
  }) {
    final s = _HomeSections(
      session: session,
      busy: busy,
      useEsp: useEsp,
      ledOn: ledOn,
      theme: theme,
      cs: cs,
      commandLines: commandLines,
      compactLed: compactLed,
    );
    return [
      StaggeredFadeIn(index: 0, child: s.connection()),
      const SizedBox(height: 20),
      StaggeredFadeIn(index: 1, child: s.led()),
      const SizedBox(height: 24),
      StaggeredFadeIn(index: 2, child: s.flight(context)),
      const SizedBox(height: 24),
      StaggeredFadeIn(index: 3, child: s.commands()),
    ];
  }

  Widget connection() => _ConnectionCard(
        useEsp: useEsp,
        busy: busy,
        urlController: session.urlController,
        onModeChanged: session.setUseEsp,
        onTestConnection: session.testConnection,
      );

  Widget led() {
    final bulb = compactLed ? 64.0 : 88.0;
    final iconSz = compactLed ? 36.0 : 48.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Indicator LED', Icons.lightbulb_outline),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: compactLed ? 12 : 20,
              horizontal: 16,
            ),
            child: Column(
              children: [
                AlivePulse(
                  active: ledOn,
                  period: const Duration(milliseconds: 1800),
                  scale: 0.04,
                  child: AnimatedContainer(
                    duration: AppMotion.mediumMs,
                    curve: Curves.easeOutCubic,
                    width: bulb,
                    height: bulb,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ledOn
                          ? Colors.amber.withValues(alpha: 0.25)
                          : cs.surfaceContainerHighest,
                      boxShadow: ledOn
                          ? [
                              BoxShadow(
                                color: Colors.amber.withValues(alpha: 0.45),
                                blurRadius: compactLed ? 16 : 24,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      Icons.lightbulb_rounded,
                      size: iconSz,
                      color: ledOn ? Colors.amber.shade700 : cs.outline,
                    ),
                  ),
                ),
                SizedBox(height: compactLed ? 8 : 12),
                AnimatedSwitcher(
                  duration: AppMotion.fastMs,
                  child: Text(
                    ledOn ? 'On' : 'Off',
                    key: ValueKey<bool>(ledOn),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(height: compactLed ? 10 : 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy || !useEsp ? null : session.syncLed,
                        icon: const Icon(Icons.sync_rounded, size: 20),
                        label: const Text('Sync'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : session.toggleLed,
                        child: busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Toggle'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget flight(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Flight', Icons.flight_takeoff_rounded),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        label: 'Arm',
                        icon: Icons.lock_open_rounded,
                        color: const Color(0xFF059669),
                        onPressed: busy
                            ? null
                            : () => _homeHoldToArm(context, session),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        label: 'Disarm',
                        icon: Icons.lock_rounded,
                        color: cs.error,
                        onPressed: busy
                            ? null
                            : () => session.droneAction('Disarm', session.drone.disarm),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        label: 'Forward',
                        icon: Icons.arrow_upward_rounded,
                        color: cs.primary,
                        filled: false,
                        onPressed: busy
                            ? null
                            : () => session.droneAction('Forward', session.drone.moveForward),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        label: 'Back',
                        icon: Icons.arrow_downward_rounded,
                        color: cs.primary,
                        filled: false,
                        onPressed: busy
                            ? null
                            : () => session.droneAction('Back', session.drone.moveBack),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget commands() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Commands', Icons.terminal_rounded),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('arm'),
                      onPressed: busy ? null : () => session.insertCommand('arm'),
                    ),
                    ActionChip(
                      label: const Text('test arm'),
                      onPressed: busy ? null : () => session.insertCommand('test arm'),
                    ),
                    ActionChip(
                      label: const Text('disarm'),
                      onPressed: busy ? null : () => session.insertCommand('disarm'),
                    ),
                    ActionChip(
                      label: const Text('esp led on'),
                      onPressed: busy ? null : () => session.insertCommand('esp led on'),
                    ),
                    ActionChip(
                      label: const Text('esp led off'),
                      onPressed: busy ? null : () => session.insertCommand('esp led off'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: session.customCommandController,
                  maxLines: commandLines,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    hintText:
                        'Any line → STM32 (arm, throttle, …). esp led on = onboard LED',
                    alignLabelWithHint: true,
                  ),
                  textInputAction: TextInputAction.newline,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy ? null : session.sendCustomLine,
                  icon: const Icon(Icons.send_rounded, size: 20),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.icon);

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.useEsp,
    required this.busy,
    required this.urlController,
    required this.onModeChanged,
    required this.onTestConnection,
  });

  final bool useEsp;
  final bool busy;
  final TextEditingController urlController;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onTestConnection;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlowWhenActive(
      active: useEsp && !busy,
      color: cs.primary,
      borderRadius: 16,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  BounceIn(
                    child: AlivePulse(
                      active: useEsp,
                      child: AnimatedContainer(
                        duration: AppMotion.mediumMs,
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: useEsp
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: AnimatedSwitcher(
                          duration: AppMotion.fastMs,
                          child: Icon(
                            useEsp ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                            key: ValueKey<bool>(useEsp),
                            color: useEsp ? cs.onPrimaryContainer : cs.outline,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: AppMotion.fastMs,
                      child: Column(
                        key: ValueKey<bool>(useEsp),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            useEsp ? 'Live ESP' : 'Offline demo',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          Text(
                            useEsp
                                ? 'Join ESP32-LED-CTRL Wi‑Fi'
                                : 'LED toggle works without hardware',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Switch(value: useEsp, onChanged: busy ? null : onModeChanged),
                ],
              ),
            if (useEsp) ...[
              const SizedBox(height: 14),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  prefixIcon: Icon(Icons.link_rounded, size: 22),
                  hintText: 'http://192.168.4.1',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : onTestConnection,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded, size: 20),
                label: const Text('Connect'),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.filled = true,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 26, color: filled ? Colors.white : color),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: filled ? Colors.white : color,
          ),
        ),
      ],
    );

    if (filled) {
      return Material(
        color: onPressed == null ? color.withValues(alpha: 0.4) : color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(child: child),
          ),
        ),
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: child,
    );
  }
}
