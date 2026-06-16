import 'rc_command_line.dart';

/// Builds `rc <thr%> <yaw> <pitch> <roll>` from transmitter sticks.
///
/// Matches [TUNING_UI_ESP_FIRMWARE.md] / Mode 2 X10 layout:
/// - Left X (rudder) → yaw ±120 °/s
/// - Left Y (throttle) → thr 0–100 % (caller supplies percent)
/// - Right Y (elevator) → pitch ±90 °/s (+ = nose up)
/// - Right X (aileron) → roll ±90 °/s (+ = roll right)
///
/// All four axes may be active at once (full stick mixing).
class RcStickFrame {
  const RcStickFrame({
    required this.throttlePercent,
    required this.leftX,
    required this.leftY,
    required this.rightX,
    required this.rightY,
    this.yawDeadzone = 0.05,
  });

  final int throttlePercent;
  final double leftX;
  final double leftY;
  final double rightX;
  final double rightY;

  /// Small center detent on rudder only (pitch/roll use full stick range).
  final double yawDeadzone;

  int get yawDps => _axisDps(_yawStick(leftX), RcCommandLine.maxYawDps);
  int get pitchDps => _axisDps(rightY, RcCommandLine.maxPitchDps);
  int get rollDps => _axisDps(rightX, RcCommandLine.maxRollDps);

  String toRcCommand() => RcCommandLine.format(
        throttlePercent: throttlePercent,
        yawDps: yawDps,
        pitchDps: pitchDps,
        rollDps: rollDps,
      );

  double _yawStick(double v) {
    final a = v.abs();
    if (a < yawDeadzone) return 0;
    final sign = v.sign;
    return sign * ((a - yawDeadzone) / (1 - yawDeadzone));
  }

  static int _axisDps(double stick, int maxDps) =>
      (stick.clamp(-1.0, 1.0) * maxDps).round().clamp(-maxDps, maxDps);
}
