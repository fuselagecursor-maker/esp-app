/// UART command lines for STM32 FC tuning (max 31 chars — ESP/STM32 limit).
///
/// Spelling from `led_remote/TUNING_UI_ESP_FIRMWARE.md` (firmware source of truth).
abstract final class FcTuneCommands {
  static const maxLineLength = 31;

  static String throttlePercent(int pct) => 'throttle ${pct.clamp(0, 100)}';

  static String armMaxUs(int us) => 'armmax ${us.clamp(1000, 2000)}';

  /// Level hold 0/0 deg — preferred over `hover` per firmware.
  static String stabilizeOn() => 'stabilize on';

  static String stabilizeOff() => 'stabilize off';

  static String hoverOn() => 'hover';

  static String hoverOff() => 'hover off';

  static String rcOff() => 'rc off';

  static String disarm() => 'disarm';

  /// 10 Hz `LIVE |` telemetry stream (faster 3D + motor readouts).
  static String debugLiveOn() => 'debug live on';

  static String debugLiveOff() => 'debug live off';

  /// Rate: `r`/`p`/`y` — attitude: `ar`/`ap`.
  static String pidAxis(String axis, double kp, double ki, double kd) {
    final line = 'pid $axis ${_fmt(kp)} ${_fmt(ki)} ${_fmt(kd)}';
    if (line.length > maxLineLength) {
      throw ArgumentError('PID command too long ($line)');
    }
    return line;
  }

  static String pidReset() => 'pid reset';

  static String pidShow() => 'pid show';

  static String filterLpf(int hz) =>
      hz <= 0 ? 'filter lpf off' : 'filter lpf $hz';

  static String filterNotchOff() => 'filter notch off';

  static String filterNotch(int hz, [double? q]) {
    final line = q == null ? 'filter notch $hz' : 'filter notch $hz ${_fmt(q)}';
    if (line.length > maxLineLength) {
      throw ArgumentError('Notch command too long ($line)');
    }
    return line;
  }

  /// Firmware bench defaults — send in order via [loadDefaultsSequence].
  static List<String> loadDefaultsSequence() => [
        disarm(),
        throttlePercent(FcTuneDefaults.idleThrottlePct),
        armMaxUs(FcTuneDefaults.armMaxUs),
        pidAxis('r', FcTuneDefaults.rateRollKp, FcTuneDefaults.rateRollKi,
            FcTuneDefaults.rateRollKd),
        pidAxis('p', FcTuneDefaults.ratePitchKp, FcTuneDefaults.ratePitchKi,
            FcTuneDefaults.ratePitchKd),
        pidAxis('y', FcTuneDefaults.rateYawKp, FcTuneDefaults.rateYawKi,
            FcTuneDefaults.rateYawKd),
        pidAxis('ar', FcTuneDefaults.attRollKp, FcTuneDefaults.attRollKi,
            FcTuneDefaults.attRollKd),
        pidAxis('ap', FcTuneDefaults.attPitchKp, FcTuneDefaults.attPitchKi,
            FcTuneDefaults.attPitchKd),
        filterLpf(FcTuneDefaults.lpfHz),
        filterNotchOff(),
      ];

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    var s = v.toStringAsFixed(4);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }
}

/// Compile-time defaults from `flight_controller.c` / `fc_config.h` (RAM on boot).
abstract final class FcTuneDefaults {
  /// After `arm`, FC forces 0%; climb via `throttle N` after stabilize.
  static const idleThrottlePct = 0;

  static const armMaxUs = 2000;

  static const armIdleUs = 1050;

  static const rateRollKp = 1.2;
  static const rateRollKi = 0.0;
  static const rateRollKd = 0.008;

  static const ratePitchKp = 1.2;
  static const ratePitchKi = 0.0;
  static const ratePitchKd = 0.008;

  static const rateYawKp = 0.8;
  static const rateYawKi = 0.0;
  static const rateYawKd = 0.004;

  static const attRollKp = 2.5;
  static const attRollKi = 0.0;
  static const attRollKd = 0.0;

  static const attPitchKp = 2.5;
  static const attPitchKi = 0.0;
  static const attPitchKd = 0.0;

  static const lpfHz = 80;
  static const notchHz = 140;
  static const notchQ = 25.0;
}
