import 'package:flutter_test/flutter_test.dart';
import 'package:led_remote/stm32_telemetry.dart';

void main() {
  const armedLine =
      'ARMED | ax=0.15 ay=0.20 az=-9.75 |a|=9.76 m/s2 | gx=-0.50 gy=0.30 gz=-0.20 dps | '
      'mR=-0.50 mP=0.30 mY=-0.20 | attR=12.50 attP=-8.20 yaw=45.30 | spR=0.00 spP=0.00 spY=0.00 | '
      'rawA=200 250 -4100 gR=-5 3 -2 seq=40000 hov=0 mode=stabilize | T=29.70 C P=989.75 hPa | '
      'throttle %=30.00 30.00 30.00 30.00 | us=1050 1050 1050 1050 | PID r/p/y=0.00 0.00 0.00';

  test('parses attR attP yaw from ARMED line', () {
    final t = FcTelemetrySnapshot.parse([armedLine]);
    expect(t.attRollDeg, closeTo(12.5, 0.01));
    expect(t.attPitchDeg, closeTo(-8.2, 0.01));
    expect(t.yawDeg, closeTo(45.3, 0.01));
    expect(t.isLiveDebug, isFalse);
  });

  test('parses LIVE debug att line', () {
    const live =
        'LIVE | ARMED ang=1 thr%=45 | att r=1.20 p=-0.50 y=90.00 | gyro r=0 gy=0 gz=0 dps';
    final t = FcTelemetrySnapshot.parse([live]);
    expect(t.attRollDeg, closeTo(1.2, 0.01));
    expect(t.attPitchDeg, closeTo(-0.5, 0.01));
    expect(t.yawDeg, closeTo(90.0, 0.01));
    expect(t.isLiveDebug, isTrue);
    expect(t.sourceLine, 'LIVE');
  });

  test('newest LIVE line wins over older ARMED line', () {
    const live =
        'LIVE | ARMED ang=1 thr%=45 | att r=5.00 p=2.00 y=10.00 | gyro r=0 gy=0 gz=0 dps';
    final t = FcTelemetrySnapshot.parse([armedLine, live]);
    expect(t.attRollDeg, closeTo(5.0, 0.01));
    expect(t.attPitchDeg, closeTo(2.0, 0.01));
    expect(t.isLiveDebug, isTrue);
  });
}
