/// Live FC data parsed only from STM32 UART lines (ESP serial log).
///
/// Spec: `led_remote/TUNING_UI_ESP_FIRMWARE.md`
class Stm32ArmedTelemetry {
  const Stm32ArmedTelemetry({
    this.armed,
    this.hoverOn,
    this.ax,
    this.ay,
    this.az,
    this.accelMagMps2,
    this.gx,
    this.gy,
    this.gz,
    this.measRateRoll,
    this.measRatePitch,
    this.measRateYaw,
    this.attRollDeg,
    this.attPitchDeg,
    this.yawDeg,
    this.spRollDps,
    this.spPitchDps,
    this.spYawDps,
    this.rawAccel = const [],
    this.rawGyro = const [],
    this.imuSeq,
    this.flightMode,
    this.pidRoll,
    this.pidPitch,
    this.pidYaw,
    this.motorPct = const [],
    this.motorUs = const [],
    this.tempC,
    this.pressureHpa,
    this.estimator,
    this.gpsStatus,
    this.magStatus,
    this.rawLine,
    this.lastUpdate,
    this.isLiveLine = false,
  });

  final bool? armed;
  final bool? hoverOn;
  final double? ax;
  final double? ay;
  final double? az;
  final double? accelMagMps2;
  final double? gx;
  final double? gy;
  final double? gz;
  /// mR/mP/mY — gyro rates deg/s (not attitude).
  final double? measRateRoll;
  final double? measRatePitch;
  final double? measRateYaw;
  final double? attRollDeg;
  final double? attPitchDeg;
  final double? yawDeg;
  final double? spRollDps;
  final double? spPitchDps;
  final double? spYawDps;
  final List<int> rawAccel;
  final List<int> rawGyro;
  final int? imuSeq;
  final String? flightMode;
  /// Rate PID outputs deg/s (before ESC scaling).
  final double? pidRoll;
  final double? pidPitch;
  final double? pidYaw;
  final List<double> motorPct;
  final List<int> motorUs;
  final double? tempC;
  final double? pressureHpa;
  final String? estimator;
  final String? gpsStatus;
  final String? magStatus;
  final String? rawLine;
  final DateTime? lastUpdate;
  final bool isLiveLine;

  bool get hasAttitude =>
      attRollDeg != null || attPitchDeg != null || yawDeg != null;

  /// True when FC sent `att r=f` / IMU invalid on a LIVE line.
  bool get imuAttitudeInvalid =>
      rawLine != null && RegExp(r'att\s+r=f\b', caseSensitive: false).hasMatch(rawLine!);

  static bool _validMotorUs(int us) => us >= 800 && us <= 2200;

  bool get hasMotors => motorUs.isNotEmpty;

  double get displayRollDeg => attRollDeg ?? 0;
  double get displayPitchDeg => attPitchDeg ?? 0;
  double get displayYawDeg => yawDeg ?? 0;

  bool get hasLiveFlight => lastUpdate != null && rawLine != null;

  bool get isLinkFresh {
    if (lastUpdate == null) return false;
    return DateTime.now().difference(lastUpdate!) < const Duration(seconds: 3);
  }

  static final _kv = RegExp(r'([\w|]+)=([-\d.]+)');

  static final _pidSlash = RegExp(
    r'PID\s+r/p/y=([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)',
    caseSensitive: false,
  );

  static final _throttlePct = RegExp(
    r'throttle\s+%=([-\d.]+(?:\s+[-\d.]+){0,3})',
    caseSensitive: false,
  );

  static final _motorUs = RegExp(
    r'\bus=((?:\d+)(?:[\s,]+\d+){0,3})',
    caseSensitive: false,
  );

  static final _accelMag = RegExp(r'\|a\|=\s*([-\d.]+)', caseSensitive: false);
  static final _rawA = RegExp(r'rawA=\s*(-?\d+)\s+(-?\d+)\s+(-?\d+)');
  static final _gR = RegExp(r'gR=\s*(-?\d+)\s+(-?\d+)\s+(-?\d+)');
  static final _mode = RegExp(r'mode=(\w+)', caseSensitive: false);

  static final _attR = RegExp(
    r'attR[=:\s]+(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final _attP = RegExp(
    r'attP[=:\s]+(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final _yawField = RegExp(
    r'\byaw[=:\s]+(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );

  static final _liveAtt = RegExp(
    r'att\s+r=(-?\d+(?:\.\d+)?)\s+p=(-?\d+(?:\.\d+)?)\s+y=(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final _liveGyro = RegExp(
    r'gyro\s+r=(-?\d+(?:\.\d+)?)\s+p=(-?\d+(?:\.\d+)?)\s+y=(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final _liveThr = RegExp(r'thr%=(-?\d+(?:\.\d+)?)', caseSensitive: false);
  static final _liveOut = RegExp(
    r'out\s+r=(-?\d+(?:\.\d+)?)\s+p=(-?\d+(?:\.\d+)?)\s+y=(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );

  static Stm32ArmedTelemetry parse(Iterable<String> lines, {DateTime? now}) {
    final list = _mergeEspUartFragments(lines);
    final ts = now ?? DateTime.now();
    Stm32ArmedTelemetry? live;
    Stm32ArmedTelemetry? flight;
    String? est;
    String? gps;
    String? mag;

    for (final raw in list.reversed) {
      var t = raw.trim();
      if (t.startsWith('>')) t = t.substring(1).trim();
      if (t.isEmpty) continue;
      final upper = t.toUpperCase();

      if (live == null && _isLiveTelemetryLine(t, upper)) {
        live = _fromLiveLine(t, ts);
      }

      if (flight == null && _isFlightLine(upper)) {
        flight = _fromFlightLine(t, ts);
      }
      if (est == null && upper.startsWith('EST')) {
        est = t.length > 48 ? '${t.substring(0, 45)}…' : t;
      }
      if (gps == null && upper.startsWith('GPS')) {
        gps = t.length > 48 ? '${t.substring(0, 45)}…' : t;
      }
      if (mag == null && upper.startsWith('MAG')) {
        mag = t.length > 48 ? '${t.substring(0, 45)}…' : t;
      }

      if (live != null && flight != null && est != null && gps != null && mag != null) {
        break;
      }
    }

    if (flight == null && live == null) {
      return Stm32ArmedTelemetry(
        estimator: est,
        gpsStatus: gps,
        magStatus: mag,
      );
    }

    // Prefer LIVE attitude when valid; keep DIS/ARM fields LIVE omits.
    if (live != null && flight != null) {
      final useLiveAtt = live.hasAttitude && !live.imuAttitudeInvalid;
      return flight.copyWith(
        attRollDeg: _pickAtt(useLiveAtt, live.attRollDeg, flight.attRollDeg),
        attPitchDeg: _pickAtt(useLiveAtt, live.attPitchDeg, flight.attPitchDeg),
        yawDeg: _pickAtt(useLiveAtt, live.yawDeg, flight.yawDeg),
        gx: live.gx ?? flight.gx,
        gy: live.gy ?? flight.gy,
        gz: live.gz ?? flight.gz,
        measRateRoll: live.measRateRoll ?? flight.measRateRoll,
        measRatePitch: live.measRatePitch ?? flight.measRatePitch,
        measRateYaw: live.measRateYaw ?? flight.measRateYaw,
        motorUs: _resolveMotorUs(list, live, flight),
        motorPct: live.motorPct.isNotEmpty ? live.motorPct : flight.motorPct,
        pidRoll: live.pidRoll ?? flight.pidRoll,
        pidPitch: live.pidPitch ?? flight.pidPitch,
        pidYaw: live.pidYaw ?? flight.pidYaw,
        rawLine: live.rawLine ?? flight.rawLine,
        lastUpdate: live.lastUpdate ?? flight.lastUpdate,
        isLiveLine: true,
        estimator: est ?? flight.estimator,
        gpsStatus: gps ?? flight.gpsStatus,
        magStatus: mag ?? flight.magStatus,
      );
    }

    final base = live ?? flight!;
    return base.copyWith(
      isLiveLine: live != null,
      motorUs: _resolveMotorUs(list, base, null),
      estimator: est ?? base.estimator,
      gpsStatus: gps ?? base.gpsStatus,
      magStatus: mag ?? base.magStatus,
    );
  }

  /// ESP UART splits long FC lines (~120 chars); `us=` often lands on a continuation chunk.
  /// Prefer LIVE-stream motor µs over newer ARMED/DISARMED poll lines (1 Hz idle us=).
  static List<int> _newestMotorUs(List<String> lines) {
    if (lines.isEmpty) return const [];

    final list = _mergeEspUartFragments(lines);

    // Prefer newest LIVE line (post-merge) over 1 Hz DIS/ARM idle us=.
    for (var i = list.length - 1; i >= 0; i--) {
      if (!list[i].toUpperCase().startsWith('LIVE')) continue;
      final motorUs = _parseMotorUs(list[i]);
      if (motorUs.isNotEmpty) return motorUs;
    }

    for (var i = list.length - 1; i >= 0; i--) {
      final motorUs = _parseMotorUs(list[i]);
      if (motorUs.isNotEmpty) return motorUs;
    }
    return const [];
  }

  /// True when any raw UART row still contains `us=` (before merge).
  static bool bufferContainsMotorField(Iterable<String> lines) {
    final re = RegExp(r'\bus=\d', caseSensitive: false);
    for (final raw in lines) {
      if (re.hasMatch(raw)) return true;
    }
    return false;
  }

  static String _stripLine(String raw) {
    var t = raw.trim();
    if (t.startsWith('>')) t = t.substring(1).trim();
    return t;
  }

  static List<int> _resolveMotorUs(
    List<String> lines,
    Stm32ArmedTelemetry primary,
    Stm32ArmedTelemetry? secondary,
  ) {
    final scanned = _newestMotorUs(lines);
    if (scanned.isNotEmpty) return scanned;
    if (primary.motorUs.isNotEmpty) return primary.motorUs;
    if (secondary != null && secondary.motorUs.isNotEmpty) {
      return secondary.motorUs;
    }
    return const [];
  }

  static List<int> _parseMotorUs(String line) {
    final usMatch = _motorUs.firstMatch(line);
    if (usMatch == null) return const [];
    final motorUs = <int>[];
    for (final part in usMatch.group(1)!.split(RegExp(r'[\s,]+'))) {
      final v = int.tryParse(part);
      if (v != null && _validMotorUs(v)) motorUs.add(v);
    }
    return motorUs;
  }

  /// ESP `uartFeedChar` flushes at ~120 chars — stitch continuation rows before parse.
  static List<String> _mergeEspUartFragments(Iterable<String> lines) {
    final merged = <String>[];
    for (final raw in lines) {
      final t = _stripLine(raw);
      if (t.isEmpty) continue;
      if (merged.isEmpty || _isUartRecordStart(t)) {
        merged.add(t);
      } else {
        merged[merged.length - 1] = '${merged.last}$t';
      }
    }
    return merged;
  }

  static bool _isUartRecordStart(String line) {
    final u = line.toUpperCase();
    return u.startsWith('LIVE') ||
        u.startsWith('DISARMED') ||
        u.startsWith('ARMED') ||
        u.startsWith('TEST_ARM') ||
        (u.startsWith('TEST ') && !u.contains('ATT')) ||
        u.startsWith('EST') ||
        u.startsWith('GPS') ||
        u.startsWith('MAG') ||
        u.startsWith('OK ') ||
        u.startsWith('ERR') ||
        u.startsWith('PID ') ||
        u.startsWith('>');
  }

  /// LIVE header or ESP UART tail chunk (`att r=` / `gyro r=` without `LIVE` prefix).
  static bool _isLiveTelemetryLine(String line, String upper) {
    if (upper.startsWith('LIVE')) return true;
    if (_liveAtt.hasMatch(line)) return true;
    return RegExp(r'gyro\s+r=', caseSensitive: false).hasMatch(line) &&
        RegExp(r'\b(us=|out\s+r=)', caseSensitive: false).hasMatch(line);
  }

  static bool _isFlightLine(String upper) =>
      upper.startsWith('ARMED') ||
      upper.startsWith('DISARMED') ||
      upper.startsWith('TEST_ARM') ||
      upper.startsWith('TEST ');

  static double? _pickAtt(bool preferLive, double? live, double? flight) {
    if (preferLive && live != null) return live;
    if (flight != null) return flight;
    return live;
  }

  static bool? _armedFromLine(String upper) {
    if (upper.contains('DISARMED')) return false;
    if (RegExp(r'\bARMED\b').hasMatch(upper)) return true;
    if (upper.startsWith('TEST_ARM') || upper.startsWith('TEST ')) return true;
    return null;
  }

  static double? _firstDouble(RegExp re, String line) {
    final m = re.firstMatch(line);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }

  Stm32ArmedTelemetry copyWith({
    bool? armed,
    bool? hoverOn,
    double? ax,
    double? ay,
    double? az,
    double? accelMagMps2,
    double? gx,
    double? gy,
    double? gz,
    double? measRateRoll,
    double? measRatePitch,
    double? measRateYaw,
    double? attRollDeg,
    double? attPitchDeg,
    double? yawDeg,
    double? spRollDps,
    double? spPitchDps,
    double? spYawDps,
    List<int>? rawAccel,
    List<int>? rawGyro,
    int? imuSeq,
    String? flightMode,
    double? pidRoll,
    double? pidPitch,
    double? pidYaw,
    List<double>? motorPct,
    List<int>? motorUs,
    double? tempC,
    double? pressureHpa,
    String? estimator,
    String? gpsStatus,
    String? magStatus,
    String? rawLine,
    DateTime? lastUpdate,
    bool? isLiveLine,
  }) {
    return Stm32ArmedTelemetry(
      armed: armed ?? this.armed,
      hoverOn: hoverOn ?? this.hoverOn,
      ax: ax ?? this.ax,
      ay: ay ?? this.ay,
      az: az ?? this.az,
      accelMagMps2: accelMagMps2 ?? this.accelMagMps2,
      gx: gx ?? this.gx,
      gy: gy ?? this.gy,
      gz: gz ?? this.gz,
      measRateRoll: measRateRoll ?? this.measRateRoll,
      measRatePitch: measRatePitch ?? this.measRatePitch,
      measRateYaw: measRateYaw ?? this.measRateYaw,
      attRollDeg: attRollDeg ?? this.attRollDeg,
      attPitchDeg: attPitchDeg ?? this.attPitchDeg,
      yawDeg: yawDeg ?? this.yawDeg,
      spRollDps: spRollDps ?? this.spRollDps,
      spPitchDps: spPitchDps ?? this.spPitchDps,
      spYawDps: spYawDps ?? this.spYawDps,
      rawAccel: rawAccel ?? this.rawAccel,
      rawGyro: rawGyro ?? this.rawGyro,
      imuSeq: imuSeq ?? this.imuSeq,
      flightMode: flightMode ?? this.flightMode,
      pidRoll: pidRoll ?? this.pidRoll,
      pidPitch: pidPitch ?? this.pidPitch,
      pidYaw: pidYaw ?? this.pidYaw,
      motorPct: motorPct ?? this.motorPct,
      motorUs: motorUs ?? this.motorUs,
      tempC: tempC ?? this.tempC,
      pressureHpa: pressureHpa ?? this.pressureHpa,
      estimator: estimator ?? this.estimator,
      gpsStatus: gpsStatus ?? this.gpsStatus,
      magStatus: magStatus ?? this.magStatus,
      rawLine: rawLine ?? this.rawLine,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      isLiveLine: isLiveLine ?? this.isLiveLine,
    );
  }

  static Stm32ArmedTelemetry _fromLiveLine(String line, DateTime now) {
    final upper = line.toUpperCase();
    final armed = _armedFromLine(upper);

    double? attR;
    double? attP;
    double? yaw;
    final attM = _liveAtt.firstMatch(line);
    if (attM != null) {
      attR = double.tryParse(attM.group(1)!);
      attP = double.tryParse(attM.group(2)!);
      yaw = double.tryParse(attM.group(3)!);
    } else {
      // Some builds mix LIVE prefix with DISARMED attR=/attP=/yaw= fields.
      attR = _firstDouble(_attR, line);
      attP = _firstDouble(_attP, line);
      yaw = _firstDouble(_yawField, line);
    }

    double? gx;
    double? gy;
    double? gz;
    final gyroM = _liveGyro.firstMatch(line);
    if (gyroM != null) {
      gx = double.tryParse(gyroM.group(1)!);
      gy = double.tryParse(gyroM.group(2)!);
      gz = double.tryParse(gyroM.group(3)!);
    }

    final motorUs = _parseMotorUs(line);

    final motorPct = <double>[];
    final thrM = _liveThr.firstMatch(line);
    if (thrM != null) {
      final v = double.tryParse(thrM.group(1)!);
      if (v != null) motorPct.add(v);
    }

    double? pidR;
    double? pidP;
    double? pidY;
    final outM = _liveOut.firstMatch(line);
    if (outM != null) {
      pidR = double.tryParse(outM.group(1)!);
      pidP = double.tryParse(outM.group(2)!);
      pidY = double.tryParse(outM.group(3)!);
    }

    return Stm32ArmedTelemetry(
      armed: armed,
      attRollDeg: attR,
      attPitchDeg: attP,
      yawDeg: yaw,
      gx: gx,
      gy: gy,
      gz: gz,
      measRateRoll: gx,
      measRatePitch: gy,
      measRateYaw: gz,
      motorUs: motorUs,
      motorPct: motorPct,
      pidRoll: pidR,
      pidPitch: pidP,
      pidYaw: pidY,
      rawLine: line.length > 120 ? '${line.substring(0, 117)}…' : line,
      lastUpdate: now,
      isLiveLine: true,
    );
  }

  static Stm32ArmedTelemetry _fromFlightLine(String line, DateTime now) {
    final upper = line.toUpperCase();
    final armed = _armedFromLine(upper) ?? false;

    final map = <String, String>{};
    for (final m in _kv.allMatches(line)) {
      var key = m.group(1)!.toLowerCase();
      if (key == '|a|') key = 'amag';
      map[key] = m.group(2)!;
    }

    final am = _accelMag.firstMatch(line);
    final accelMag = am != null ? double.tryParse(am.group(1)!) : _dbl(map, 'amag');

    final attRoll = _firstDouble(_attR, line) ?? _dbl(map, 'attr');
    final attPitch = _firstDouble(_attP, line) ?? _dbl(map, 'attp');
    final yaw = _firstDouble(_yawField, line) ?? _dbl(map, 'yaw');

    bool? hov;
    final h = map['hov'];
    if (h == '0' || h == '1') hov = h == '1';

    double? pidR;
    double? pidP;
    double? pidY;
    final pidBlock = _pidSlash.firstMatch(line);
    if (pidBlock != null) {
      pidR = double.tryParse(pidBlock.group(1)!);
      pidP = double.tryParse(pidBlock.group(2)!);
      pidY = double.tryParse(pidBlock.group(3)!);
    }

    final motorPct = <double>[];
    final thrMatch = _throttlePct.firstMatch(line);
    if (thrMatch != null) {
      for (final part in thrMatch.group(1)!.split(RegExp(r'\s+'))) {
        final v = double.tryParse(part);
        if (v != null) motorPct.add(v);
      }
    }

    final motorUs = _parseMotorUs(line);

    final rawA = <int>[];
    final ra = _rawA.firstMatch(line);
    if (ra != null) {
      for (var i = 1; i <= 3; i++) {
        rawA.add(int.parse(ra.group(i)!));
      }
    }

    final rawG = <int>[];
    final rg = _gR.firstMatch(line);
    if (rg != null) {
      for (var i = 1; i <= 3; i++) {
        rawG.add(int.parse(rg.group(i)!));
      }
    }

    final modeM = _mode.firstMatch(line);

    return Stm32ArmedTelemetry(
      armed: armed,
      hoverOn: hov,
      ax: _dbl(map, 'ax'),
      ay: _dbl(map, 'ay'),
      az: _dbl(map, 'az'),
      accelMagMps2: accelMag,
      gx: _dbl(map, 'gx'),
      gy: _dbl(map, 'gy'),
      gz: _dbl(map, 'gz'),
      measRateRoll: _dbl(map, 'mr'),
      measRatePitch: _dbl(map, 'mp'),
      measRateYaw: _dbl(map, 'my'),
      attRollDeg: attRoll,
      attPitchDeg: attPitch,
      yawDeg: yaw,
      spRollDps: _dbl(map, 'spr'),
      spPitchDps: _dbl(map, 'spp'),
      spYawDps: _dbl(map, 'spy'),
      rawAccel: rawA,
      rawGyro: rawG,
      imuSeq: _int(map, 'seq'),
      flightMode: modeM?.group(1),
      pidRoll: pidR,
      pidPitch: pidP,
      pidYaw: pidY,
      motorPct: motorPct,
      motorUs: motorUs,
      tempC: _dbl(map, 't'),
      pressureHpa: _dbl(map, 'p'),
      rawLine: line.length > 120 ? '${line.substring(0, 117)}…' : line,
      lastUpdate: now,
    );
  }

  static double? _dbl(Map<String, String> m, String key) {
    final v = m[key];
    if (v == null) return null;
    return double.tryParse(v);
  }

  static int? _int(Map<String, String> m, String key) {
    final v = m[key];
    if (v == null) return null;
    return int.tryParse(v);
  }

  String formatNum(double? v, {int decimals = 1}) {
    if (v == null) return '—';
    if (decimals == 0) return v.round().toString();
    return v.toStringAsFixed(decimals);
  }

  String formatAge() {
    if (lastUpdate == null) return 'no data';
    final ms = DateTime.now().difference(lastUpdate!).inMilliseconds;
    if (ms < 1000) return '${ms}ms ago';
    return '${(ms / 1000).toStringAsFixed(1)}s ago';
  }
}

/// Parsed `pid show` / `pid` readback lines from serial.
class Stm32PidGains {
  const Stm32PidGains({
    this.rateRoll,
    this.ratePitch,
    this.rateYaw,
    this.attRoll,
    this.attPitch,
  });

  final List<double>? rateRoll;
  final List<double>? ratePitch;
  final List<double>? rateYaw;
  final List<double>? attRoll;
  final List<double>? attPitch;

  static final _line = RegExp(
    r'^pid\s+(r|p|y|ar|ap)\s+([0-9]+(?:\.[0-9]+)?)\s+([0-9]+(?:\.[0-9]+)?)\s+([0-9]+(?:\.[0-9]+)?)\s*$',
    caseSensitive: false,
  );

  /// Newest matching lines win per axis.
  static Stm32PidGains? parse(Iterable<String> lines) {
    List<double>? r;
    List<double>? p;
    List<double>? y;
    List<double>? ar;
    List<double>? ap;

    for (final raw in lines.toList().reversed) {
      var t = raw.trim();
      if (t.startsWith('>')) t = t.substring(1).trim();
      final m = _line.firstMatch(t);
      if (m == null) continue;
      final gains = [
        double.parse(m.group(2)!),
        double.parse(m.group(3)!),
        double.parse(m.group(4)!),
      ];
      switch (m.group(1)!.toLowerCase()) {
        case 'r':
          r ??= gains;
        case 'p':
          p ??= gains;
        case 'y':
          y ??= gains;
        case 'ar':
          ar ??= gains;
        case 'ap':
          ap ??= gains;
      }
      if (r != null && p != null && y != null && ar != null && ap != null) break;
    }

    if (r == null && p == null && y == null && ar == null && ap == null) {
      return null;
    }
    return Stm32PidGains(
      rateRoll: r,
      ratePitch: p,
      rateYaw: y,
      attRoll: ar,
      attPitch: ap,
    );
  }

  bool get isComplete =>
      rateRoll != null &&
      ratePitch != null &&
      rateYaw != null &&
      attRoll != null &&
      attPitch != null;
}
