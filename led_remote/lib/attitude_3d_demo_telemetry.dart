import 'dart:math' as math;

import 'stm32_armed_telemetry.dart';

/// Removable bench demo — delete this file + 3D page DEMO toggle to drop it.
abstract final class Attitude3DDemoTelemetry {
  static Stm32ArmedTelemetry at(double tSec) {
    final roll = 22 * math.sin(tSec * 0.65);
    final pitch = 16 * math.sin(tSec * 0.45 + 0.8);
    final yaw = (tSec * 18) % 360 - 180;
    final base = 1750;
    final motorUs = [
      base + (80 * math.sin(tSec * 6)).round(),
      base + (75 * math.sin(tSec * 6 + 1.2)).round(),
      base + (78 * math.sin(tSec * 6 + 2.4)).round(),
      base + (72 * math.sin(tSec * 6 + 3.6)).round(),
    ];
    return Stm32ArmedTelemetry(
      armed: false,
      attRollDeg: roll,
      attPitchDeg: pitch,
      yawDeg: yaw,
      motorUs: motorUs,
      rawLine:
          'DEMO | att r=${roll.toStringAsFixed(2)} p=${pitch.toStringAsFixed(2)} '
          'y=${yaw.toStringAsFixed(1)} | us=${motorUs.join(' ')}',
      lastUpdate: DateTime.now(),
      isLiveLine: true,
    );
  }
}
