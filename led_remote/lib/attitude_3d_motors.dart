/// Motor / propeller visuals for the 3D attitude view (from FC `us=` telemetry).
class Attitude3DMotors {
  Attitude3DMotors._();

  static const idleUs = 1000;
  static const armIdleUs = 1050;
  static const maxUs = 2000;

  /// Quad X: alternate CW / CCW for prop spin direction (visual only).
  static const spinDirections = [1.0, -1.0, 1.0, -1.0];

  /// Normalized throttle activity 0..1 from ESC µs.
  static double activity(int us) {
    if (!isValidUs(us) || us <= idleUs) return 0;
    return ((us - idleUs) / (maxUs - idleUs)).clamp(0.0, 1.0);
  }

  /// Prop spin speed (rad/s) from commanded µs — cosmetic, not measured RPM.
  static double spinRadPerSec(int us) {
    if (!isValidUs(us) || us <= armIdleUs) return 0;
    final t = ((us - armIdleUs) / (maxUs - armIdleUs)).clamp(0.0, 1.0);
    return t * 32.0;
  }

  /// Real ESC µs band; rejects UART garbage like 2684354560.
  static bool isValidUs(int us) => us >= 800 && us <= 2200;

  static int sanitizeUs(int us) => isValidUs(us) ? us : idleUs;

  /// Ensure exactly 4 motor values (pad with idle if partial parse).
  static List<int> normalizeUs(List<int> raw) {
    if (raw.isEmpty) return const [idleUs, idleUs, idleUs, idleUs];
    final out = raw.take(4).map(sanitizeUs).toList();
    while (out.length < 4) {
      out.add(idleUs);
    }
    return out;
  }

  static String formatUsList(List<int> us) {
    final n = normalizeUs(us);
    return 'M1=${n[0]} M2=${n[1]} M3=${n[2]} M4=${n[3]}';
  }
}
