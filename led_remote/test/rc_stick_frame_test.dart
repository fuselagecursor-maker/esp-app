import 'package:flutter_test/flutter_test.dart';
import 'package:led_remote/rc_stick_frame.dart';

void main() {
  test('Mode 2 mapping: left X=yaw, right Y=pitch, right X=roll', () {
    const frame = RcStickFrame(
      throttlePercent: 40,
      leftX: 1,
      leftY: 0,
      rightX: 0,
      rightY: -1,
      yawDeadzone: 0,
    );
    expect(frame.yawDps, 120);
    expect(frame.pitchDps, -90);
    expect(frame.rollDps, 0);
    expect(frame.toRcCommand(), 'rc 40 120 -90 0');
  });

  test('bench example rc 45 0 -20 30', () {
    const frame = RcStickFrame(
      throttlePercent: 45,
      leftX: 0,
      leftY: 0,
      rightX: 30 / 90,
      rightY: -20 / 90,
      yawDeadzone: 0,
    );
    expect(frame.toRcCommand(), 'rc 45 0 -20 30');
  });

  test('full mixing: yaw + pitch + roll together', () {
    const frame = RcStickFrame(
      throttlePercent: 50,
      leftX: 0.5,
      leftY: 0,
      rightX: 0.5,
      rightY: -0.5,
      yawDeadzone: 0,
    );
    expect(frame.yawDps, 60);
    expect(frame.pitchDps, -45);
    expect(frame.rollDps, 45);
    expect(frame.toRcCommand(), 'rc 50 60 -45 45');
  });

  test('yaw deadzone only affects rudder', () {
    const frame = RcStickFrame(
      throttlePercent: 0,
      leftX: 0.03,
      leftY: 0,
      rightX: 0.5,
      rightY: 0,
      yawDeadzone: 0.05,
    );
    expect(frame.yawDps, 0);
    expect(frame.rollDps, 45);
  });
}
