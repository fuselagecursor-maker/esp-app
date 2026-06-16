import 'dart:async';

import 'package:flutter/foundation.dart';

import 'stm32_armed_telemetry.dart';

/// One shared `/drone/serial` poll for the whole app (avoids ESP + UI overload).
class SerialLogCache extends ChangeNotifier {
  SerialLogCache({required Future<List<String>> Function() fetchFromDrone})
      : _fetchFromDrone = fetchFromDrone;

  final Future<List<String>> Function() _fetchFromDrone;

  static final _pollInterval =
      Duration(milliseconds: kIsWeb ? 1600 : 1300);
  static final _fastPollInterval = Duration(milliseconds: kIsWeb ? 520 : 480);
  static final _turboPollInterval = Duration(milliseconds: kIsWeb ? 140 : 110);

  List<String> _lines = const [];
  bool _active = false;
  bool _fastPoll = false;
  bool _turboPoll = false;
  /// `null` = infer from LIVE lines; `true`/`false` = user toggled debug live.
  bool? _debugLivePreference;
  bool _inFlight = false;
  String _attitudeSig = '';
  String _valueSig = '';
  String _motorSig = '';
  DateTime? _lastNotifyAt;
  Timer? _timer;

  List<String> get lines => _lines;

  bool? get debugLivePreference => _debugLivePreference;

  /// Effective debug-live state for UI (user preference or LIVE telemetry).
  bool debugLiveEffective(Stm32ArmedTelemetry telemetry) {
    if (_debugLivePreference != null) return _debugLivePreference!;
    return telemetry.isLiveLine && telemetry.isLinkFresh;
  }

  void setDebugLivePreference(bool enabled) {
    if (_debugLivePreference == enabled) return;
    _debugLivePreference = enabled;
    notifyListeners();
  }

  Duration get _interval {
    if (_turboPoll) return _turboPollInterval;
    if (_fastPoll) return _fastPollInterval;
    return _pollInterval;
  }

  /// Attitude page @ ~2 Hz FC telemetry.
  void setFastPoll(bool enabled) {
    if (_fastPoll == enabled) return;
    _fastPoll = enabled;
    if (_active) _restartTimer();
  }

  /// Attitude page @ debug live (~10 Hz) — matches `debug live on`.
  void setTurboPoll(bool enabled) {
    if (_turboPoll == enabled) return;
    _turboPoll = enabled;
    if (_active) _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => refresh());
  }

  void setActive(bool active) {
    if (active == _active) return;
    _active = active;
    if (!active) {
      _timer?.cancel();
      _timer = null;
      _lines = const [];
      _attitudeSig = '';
      _valueSig = '';
      _motorSig = '';
      _lastNotifyAt = null;
      notifyListeners();
      return;
    }
    _timer?.cancel();
    _restartTimer();
    Timer(const Duration(milliseconds: 600), refresh);
  }

  Future<List<String>> getLines() async {
    if (!_active) return const [];
    if (_lines.isNotEmpty) return List.unmodifiable(_lines);
    await refresh();
    return List.unmodifiable(_lines);
  }

  Future<void> refresh() async {
    if (!_active || _inFlight) return;
    _inFlight = true;
    try {
      final next = await _fetchFromDrone();
      final attSig = _newestAttitudeSig(next);
      final valueSig = _attitudeValueSig(next);
      final motorSig = _motorValueSig(next);
      final changed = !_listEqual(_lines, next) ||
          attSig != _attitudeSig ||
          valueSig != _valueSig ||
          motorSig != _motorSig;
      final now = DateTime.now();
      final heartbeatDue = _turboPoll &&
          (_lastNotifyAt == null ||
              now.difference(_lastNotifyAt!).inMilliseconds >= 350);
      if (changed || heartbeatDue) {
        _lines = next;
        if (changed) {
          _attitudeSig = attSig;
          _valueSig = valueSig;
          _motorSig = motorSig;
        }
        _lastNotifyAt = now;
        notifyListeners();
      }
    } catch (_) {
      // Keep last good lines.
    } finally {
      _inFlight = false;
    }
  }

  static String _newestAttitudeSig(List<String> lines) {
    for (final line in lines.reversed) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final l = t.toLowerCase();
      if (l.startsWith('live') ||
          l.startsWith('armed |') ||
          l.startsWith('disarmed |') ||
          l.contains('attr=') ||
          l.contains('att r=') ||
          l.contains('us=')) {
        return t;
      }
    }
    return '';
  }

  static String _attitudeValueSig(List<String> lines) {
    final t = Stm32ArmedTelemetry.parse(lines);
    if (!t.hasAttitude) return '';
    return '${t.attRollDeg?.toStringAsFixed(2)}|'
        '${t.attPitchDeg?.toStringAsFixed(2)}|'
        '${t.yawDeg?.toStringAsFixed(1)}|'
        '${t.isLiveLine}|'
        '${t.rawLine ?? ''}';
  }

  static String _motorValueSig(List<String> lines) {
    final t = Stm32ArmedTelemetry.parse(lines);
    if (!t.hasMotors) return '';
    return t.motorUs.join(',');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  static bool _listEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
