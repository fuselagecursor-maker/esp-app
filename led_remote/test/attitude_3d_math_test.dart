import 'package:flutter_test/flutter_test.dart';
import 'package:led_remote/attitude_3d_math.dart';

void main() {
  test('level quad deck sits on ground plane (Y=0)', () {
    for (final tip in Attitude3DMath.motorTips()) {
      final w = Attitude3DMath.bodyToWorld(
        tip,
        rollDeg: 0,
        pitchDeg: 0,
        yawDeg: 0,
      );
      expect(w.y, closeTo(0, 1e-9));
    }
  });

  test('body Z points down when level', () {
    final down = Attitude3DMath.bodyToWorld(
      const Vec3(0, 0, 1),
      rollDeg: 0,
      pitchDeg: 0,
      yawDeg: 0,
    );
    expect(down.y, closeTo(-1, 1e-9));
    expect(down.x, closeTo(0, 1e-9));
    expect(down.z, closeTo(0, 1e-9));
  });

  test('roll tilts quad off the ground plane', () {
    final w = Attitude3DMath.bodyToWorld(
      Attitude3DMath.motorTips().first,
      rollDeg: 12,
      pitchDeg: 0,
      yawDeg: 0,
    );
    expect(w.y.abs(), greaterThan(0.05));
  });

  test('isNearLevel respects tolerance', () {
    expect(Attitude3DMath.isNearLevel(0, 0), isTrue);
    expect(Attitude3DMath.isNearLevel(1.5, -1.0), isTrue);
    expect(Attitude3DMath.isNearLevel(5, 0), isFalse);
  });
}
