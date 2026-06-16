/// Shared `rc <thr%> <yaw> <pitch> <roll>` builder for Control + Manual tabs.
abstract final class RcCommandLine {
  static const maxYawDps = 120;
  static const maxPitchDps = 90;
  static const maxRollDps = 90;

  /// Same rounding/clamps as [ManualControlPage._rcCommand].
  static String format({
    required int throttlePercent,
    required num yawDps,
    required num pitchDps,
    required num rollDps,
  }) {
    final thr = throttlePercent.clamp(0, 100);
    final yaw = yawDps.round().clamp(-maxYawDps, maxYawDps);
    final pitch = pitchDps.round().clamp(-maxPitchDps, maxPitchDps);
    final roll = rollDps.round().clamp(-maxRollDps, maxRollDps);
    return 'rc $thr $yaw $pitch $roll';
  }
}
