import 'package:flutter_test/flutter_test.dart';
import 'package:led_remote/attitude_3d_motors.dart';

void main() {
  test('activity maps us to 0..1', () {
    expect(Attitude3DMotors.activity(1000), 0);
    expect(Attitude3DMotors.activity(1050), closeTo(0.05, 0.01));
    expect(Attitude3DMotors.activity(2000), 1);
  });

  test('spin is zero at arm idle', () {
    expect(Attitude3DMotors.spinRadPerSec(1000), 0);
    expect(Attitude3DMotors.spinRadPerSec(1050), 0);
    expect(Attitude3DMotors.spinRadPerSec(1600), greaterThan(10));
  });

  test('normalizeUs pads to four motors', () {
    expect(
      Attitude3DMotors.normalizeUs([1580, 1575]),
      [1580, 1575, 1000, 1000],
    );
    expect(
      Attitude3DMotors.normalizeUs([]),
      [1000, 1000, 1000, 1000],
    );
  });
}
