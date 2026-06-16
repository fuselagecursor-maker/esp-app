/// Top-deck analog gauge inputs (throttle live; other axes optional).
class TxTelemetrySnapshot {
  const TxTelemetrySnapshot({
    required this.throttle01,
    this.yaw,
    this.pitch,
    this.roll,
  });

  /// Throttle 0.0 (min) … 1.0 (full).
  final double throttle01;

  /// Yaw −1 … 1 (center = 0). Null → [dummyYaw].
  final double? yaw;

  /// Pitch −1 … 1. Null → [dummyPitch].
  final double? pitch;

  /// Roll −1 … 1. Null → [dummyRoll].
  final double? roll;

  double get yawNorm => yaw ?? 0;
  double get pitchNorm => pitch ?? 0;
  double get rollNorm => roll ?? 0;

  /// From control sticks / throttle. Pass [yaw], [pitch], [roll] when live data exists.
  factory TxTelemetrySnapshot.fromControl({
    required int throttlePercent,
    double? yaw,
    double? pitch,
    double? roll,
  }) {
    return TxTelemetrySnapshot(
      throttle01: (throttlePercent.clamp(0, 100)) / 100.0,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
    );
  }
}
