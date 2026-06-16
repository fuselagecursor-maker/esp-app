class FcTelemetrySnapshot {
  const FcTelemetrySnapshot({
    this.armed,
    this.hoverOn,
    this.setpointPitchDps,
    this.setpointRollDps,
    this.setpointYawDps,
    this.attRollDeg,
    this.attPitchDeg,
    this.rollDeg,
    this.pitchDeg,
    this.yawDeg,
    this.throttlePercent,
    this.latitude,
    this.longitude,
    this.rawLine,
    this.sourceLine,
    this.isLiveDebug = false,

  });

  final bool? armed;
  final bool? hoverOn;
  final double? setpointPitchDps;
  final double? setpointRollDps;
  final double? setpointYawDps;
  final double? attRollDeg;
  final double? attPitchDeg;
  final double? rollDeg;
  final double? pitchDeg;
  final double? yawDeg;
  final int? throttlePercent;
  final double? latitude;
  final double? longitude;
  final String? rawLine;
  /// Newest telemetry line used for attitude (LIVE | or ARMED |).
  final String? sourceLine;
  final bool isLiveDebug;

  double get displayRollDeg => attRollDeg ?? rollDeg ?? 0;
  double get displayPitchDeg => attPitchDeg ?? pitchDeg ?? 0;
  double get displayYawDeg => yawDeg ?? 0;

  bool get hasAttitude =>
      attRollDeg != null || attPitchDeg != null || yawDeg != null;

  bool get hasGps =>
      latitude != null &&
      longitude != null &&
      latitude!.abs() <= 90 &&
      longitude!.abs() <= 180;

  bool get hasData =>
      armed != null ||
      attRollDeg != null ||
      attPitchDeg != null ||
      setpointPitchDps != null ||
      setpointRollDps != null ||
      setpointYawDps != null ||
      rollDeg != null ||
      pitchDeg != null ||
      yawDeg != null ||
      throttlePercent != null ||
      hasGps;

  static final _hover = RegExp(r'\bhov=(\d)', caseSensitive: false);
  static final _attR = RegExp(r'attR[=:\s]+(-?\d+(?:\.\d+)?)', caseSensitive: false);
  static final _attP = RegExp(r'attP[=:\s]+(-?\d+(?:\.\d+)?)', caseSensitive: false);
  static final _liveAtt = RegExp(
    r'att\s+r=(-?\d+(?:\.\d+)?)\s+p=(-?\d+(?:\.\d+)?)\s+y=(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final _spP = RegExp(r'spP[:\s=]+(-?\d+(?:\.\d+)?)', caseSensitive: false);
  static final _spR = RegExp(r'spR[:\s=]+(-?\d+(?:\.\d+)?)', caseSensitive: false);
  static final _spY = RegExp(r'spY[:\s=]+(-?\d+(?:\.\d+)?)', caseSensitive: false);
  static final _roll = RegExp(r'\broll[:\s=]+(-?\d+(?:\.\d+)?)', caseSensitive: false);
  static final _pitch = RegExp(r'\bpitch[:\s=]+(-?\d+(?:\.\d+)?)', caseSensitive: false);
  static final _yaw = RegExp(r'\byaw[:\s=]+(-?\d+(?:\.\d+)?)', caseSensitive: false);
  static final _thr = RegExp(
    r'\b(?:thr|throttle)[:\s=]+(\d{1,3})\b',
    caseSensitive: false,
  );
  static final _lat = RegExp(
    r'\b(?:lat|latitude)[:\s=]+(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final _lon = RegExp(
    r'\b(?:lon|lng|longitude|long)[:\s=]+(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final _armedWord = RegExp(r'\bARMED\b', caseSensitive: false);
  static final _disarmedWord = RegExp(r'\bDISARMED\b', caseSensitive: false);

  /// Prefer the **newest** attitude line (LIVE @10Hz or ARMED @2Hz), not a merge of old lines.
  static FcTelemetrySnapshot parse(Iterable<String> lines) {
    final list = lines.toList();
    for (final line in list.reversed) {
      final t = line.trim();
      if (t.isEmpty || !_isAttitudeSourceLine(t)) continue;
      final snap = _fromLine(t);
      if (snap.hasAttitude) return snap;
    }
    return _mergeScan(list);
  }

  static bool _isAttitudeSourceLine(String t) {
    final l = t.toLowerCase();
    return l.startsWith('live |') ||
        l.startsWith('armed |') ||
        l.startsWith('disarmed |') ||
        l.contains('attr=');
  }

  static FcTelemetrySnapshot _fromLine(String t) {
    final lower = t.toLowerCase();
    bool? armed;
    if (_disarmedWord.hasMatch(t)) {
      armed = false;
    } else if (_armedWord.hasMatch(t)) {
      armed = true;
    }

    double? attR = _firstDouble(_attR, t);
    double? attP = _firstDouble(_attP, t);
    double? yaw;
    final live = _liveAtt.firstMatch(t);
    if (live != null) {
      attR ??= double.tryParse(live.group(1)!);
      attP ??= double.tryParse(live.group(2)!);
      yaw = double.tryParse(live.group(3)!);
    }
    yaw ??= _firstDouble(_yaw, t);

    final short = t.length > 52 ? '${t.substring(0, 49)}…' : t;
    return FcTelemetrySnapshot(
      armed: armed,
      hoverOn: _hover.firstMatch(t)?.group(1) == '1',
      setpointPitchDps: _firstDouble(_spP, t),
      setpointRollDps: _firstDouble(_spR, t),
      setpointYawDps: _firstDouble(_spY, t),
      attRollDeg: attR,
      attPitchDeg: attP,
      rollDeg: _firstDouble(_roll, t),
      pitchDeg: _firstDouble(_pitch, t),
      yawDeg: yaw,
      throttlePercent: _firstInt(_thr, t),
      latitude: _firstDouble(_lat, t),
      longitude: _firstDouble(_lon, t),
      rawLine: short,
      sourceLine: t.startsWith('LIVE') ? 'LIVE' : t.split('|').first.trim(),
      isLiveDebug: lower.startsWith('live |'),
    );
  }

  /// Fallback: merge fields from multiple lines (GPS, armed state, etc.).
  static FcTelemetrySnapshot _mergeScan(List<String> list) {
    bool? armed;
    bool? hoverOn;
    double? spP;
    double? spR;
    double? spY;
    double? attR;
    double? attP;
    double? roll;
    double? pitch;
    double? yaw;
    int? thr;
    double? lat;
    double? lon;
    String? lastTel;
    String? source;
    var isLive = false;

    for (final line in list.reversed) {
      final t = line.trim();
      if (t.isEmpty) continue;

      if (armed == null) {
        if (_disarmedWord.hasMatch(t)) {
          armed = false;
        } else if (_armedWord.hasMatch(t)) {
          armed = true;
        }
      }

      hoverOn ??= _hover.firstMatch(t)?.group(1) == '1';
      spP ??= _firstDouble(_spP, t);
      spR ??= _firstDouble(_spR, t);
      spY ??= _firstDouble(_spY, t);

      if (attR == null || attP == null || yaw == null) {
        final snap = _fromLine(t);
        attR ??= snap.attRollDeg;
        attP ??= snap.attPitchDeg;
        yaw ??= snap.yawDeg;
        if (snap.hasAttitude && source == null) {
          source = snap.sourceLine;
          isLive = snap.isLiveDebug;
        }
      }

      roll ??= _firstDouble(_roll, t);
      pitch ??= _firstDouble(_pitch, t);
      thr ??= _firstInt(_thr, t);
      lat ??= _firstDouble(_lat, t);
      lon ??= _firstDouble(_lon, t);

      lastTel ??= t.length > 48 ? '${t.substring(0, 45)}…' : t;

      if (armed != null && attR != null && attP != null && yaw != null) break;
    }

    return FcTelemetrySnapshot(
      armed: armed,
      hoverOn: hoverOn,
      setpointPitchDps: spP,
      setpointRollDps: spR,
      setpointYawDps: spY,
      attRollDeg: attR,
      attPitchDeg: attP,
      rollDeg: roll,
      pitchDeg: pitch,
      yawDeg: yaw,
      throttlePercent: thr,
      latitude: lat,
      longitude: lon,
      rawLine: lastTel,
      sourceLine: source,
      isLiveDebug: isLive,
    );
  }

  static double? _firstDouble(RegExp re, String line) {
    final m = re.firstMatch(line);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }

  static int? _firstInt(RegExp re, String line) {
    final m = re.firstMatch(line);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  String formatNum(double? v, {int decimals = 0}) {
    if (v == null) return '—';
    if (decimals == 0) return v.round().toString();
    return v.toStringAsFixed(decimals);
  }
}
