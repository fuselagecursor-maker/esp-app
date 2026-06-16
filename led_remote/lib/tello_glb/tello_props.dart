import '../attitude_3d_motors.dart';

/// Prop nodes inside [TelloGlbAsset] and motor → spin mapping.
abstract final class TelloGlbProps {
  static const modelElementId = 'tello_glb_mv';

  /// Parent nodes for each prop assembly (M1…M4, front-left CW order in model).
  static const propNodeNames = [
    'pervane.001_1',
    'pervane.002_3',
    'pervane.003_5',
    'pervane.004_7',
  ];

  static List<double> spinRadPerSec(List<int> motorUs) {
    final us = Attitude3DMotors.normalizeUs(motorUs);
    return [
      for (var i = 0; i < 4; i++)
        Attitude3DMotors.spinRadPerSec(us[i]) * Attitude3DMotors.spinDirections[i],
    ];
  }

  static bool anySpinning(List<double> radPerSec) =>
      radPerSec.any((r) => r.abs() > 0.05);

  static String speedsCsv(List<double> radPerSec) =>
      radPerSec.map((r) => r.toStringAsFixed(3)).join(',');

  /// GLB nose is along +X; model-viewer / glTF front is +Z — 90° Y correction.
  static const modelYawOffsetDeg = -90.0;

  /// model-viewer `orientation` — roll pitch yaw → Euler(pitch,yaw,roll,'YXZ').
  /// FC pitch+ is nose-down; viewer pitch+ is nose-up → negate pitch.
  static String orientation({
    required double rollDeg,
    required double pitchDeg,
    required double yawDeg,
  }) {
    final mvYaw = _normDeg(yawDeg + modelYawOffsetDeg);
    return '${rollDeg.toStringAsFixed(2)}deg '
        '${(-pitchDeg).toStringAsFixed(2)}deg '
        '${mvYaw.toStringAsFixed(2)}deg';
  }

  static double _normDeg(double d) {
    var x = d % 360.0;
    if (x > 180.0) x -= 360.0;
    if (x <= -180.0) x += 360.0;
    return x;
  }
}
