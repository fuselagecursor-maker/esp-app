import 'package:flutter_test/flutter_test.dart';
import 'package:led_remote/stm32_armed_telemetry.dart';

void main() {
  const sample =
      '> ARMED | ax=0.25 ay=0.12 az=9.82 |a|=9.82 m/s2 | gx=0.14 gy=0.09 gz=1.24 dps | '
      'mR=0.14 mP=0.09 mY=1.24 | attR=0.30 attP=0.15 yaw=0.46 | spR=0.16 spP=11.27 spY=0.00 | '
      'rawA=443 -201 16916 gR=-9 29 91 seq=23684 hov=1 mode=stabilize | T=26.96 C P=991.32 hPa | '
      'throttle %=5.80 0.00 6.20 0.00 | us=1058 1000 1062 1000 | PID r/p/y=-1.66 27.01 0.53';

  test('parses real ARMED line and status lines', () {
    final t = Stm32ArmedTelemetry.parse([
      'MAG NA (no MMC5983 at boot)',
      'EST mahony',
      'GPS NA (USART2)',
      sample,
    ], now: DateTime(2020, 1, 1, 12, 0, 0));

    expect(t.hasLiveFlight, isTrue);
    expect(t.armed, isTrue);
    expect(t.hoverOn, isTrue);
    expect(t.attRollDeg, closeTo(0.30, 0.01));
    expect(t.measRateRoll, closeTo(0.14, 0.01));
    expect(t.flightMode, 'stabilize');
    expect(t.spPitchDps, closeTo(11.27, 0.01));
    expect(t.pidPitch, closeTo(27.01, 0.01));
  });

  test('LIVE line overrides attitude and motor us', () {
    const live =
        'LIVE | ARMED ang=1 thr%=45 | att r=1.20 p=-0.50 y=90.00 | '
        'gyro r=-1.46 p=-1.27 y=-1.07 dps | set r=0.50 p=-0.20 y=0.00 | '
        'out r=-2.00 p=1.50 y=0.65 | us=1580 1575 1585 1578';
    final t = Stm32ArmedTelemetry.parse([sample, live]);
    expect(t.isLiveLine, isTrue);
    expect(t.attRollDeg, closeTo(1.2, 0.01));
    expect(t.attPitchDeg, closeTo(-0.5, 0.01));
    expect(t.motorUs, [1580, 1575, 1585, 1578]);
    expect(t.pidPitch, closeTo(1.5, 0.01));
    expect(t.hoverOn, isTrue);
  });

  test('parses pid show lines', () {
    final g = Stm32PidGains.parse([
      'pid r 1.2 0 0.008',
      'pid p 1.2 0 0.008',
      'pid y 0.8 0 0.004',
      'pid ar 2.5 0 0',
      'pid ap 2.5 0 0',
    ]);
    expect(g?.isComplete, isTrue);
    expect(g!.rateRoll![0], closeTo(1.2, 0.001));
    expect(g.attPitch![2], 0);
  });

  test('parses DISARMED line attR attP yaw', () {
    const disarmed =
        'DISARMED | ax=0.02 ay=0.01 az=-9.81 |a|=9.81 m/s2 | gx=0.00 gy=0.00 gz=0.00 dps | '
        'mR=0.00 mP=0.00 mY=0.00 | attR=12.50 attP=-8.20 yaw=45.30 | spR=0.00 spP=0.00 spY=0.00 | '
        'rawA=120 80 -4050 gR=0 0 0 seq=12045 hov=0 mode=stabilize | T=29.50 C P=989.80 hPa | '
        'throttle %=0.00 0.00 0.00 0.00 | us=1000 1000 1000 1000 | PID r/p/y=0.00 0.00 0.00';
    final t = Stm32ArmedTelemetry.parse([disarmed]);
    expect(t.armed, isFalse);
    expect(t.attRollDeg, closeTo(12.5, 0.01));
    expect(t.attPitchDeg, closeTo(-8.2, 0.01));
    expect(t.yawDeg, closeTo(45.3, 0.01));
    expect(t.isLiveLine, isFalse);
  });

  test('LIVE DISARMED line is not marked armed', () {
    const live =
        'LIVE | DISARMED ang=0 thr%=0 | att r=15.00 p=-6.00 y=90.00 | '
        'gyro r=0 p=0 y=0 dps | us=1000 1000 1000 1000';
    final t = Stm32ArmedTelemetry.parse([live]);
    expect(t.armed, isFalse);
    expect(t.isLiveLine, isTrue);
    expect(t.attRollDeg, closeTo(15.0, 0.01));
    expect(t.attPitchDeg, closeTo(-6.0, 0.01));
  });

  test('LIVE without pipe-space still parses', () {
    const live =
        'LIVE| DISARMED ang=0 thr%=0 | att r=3.00 p=1.00 y=45.00 | '
        'gyro r=0 p=0 y=0 dps | us=1100 1100 1100 1100';
    final t = Stm32ArmedTelemetry.parse([live]);
    expect(t.isLiveLine, isTrue);
    expect(t.attRollDeg, closeTo(3.0, 0.01));
    expect(t.hasMotors, isTrue);
  });

  test('LIVE with attR= fallback fields', () {
    const live =
        'LIVE | DISARMED | attR=7.00 attP=-2.00 yaw=180.00 | us=1200 1200 1200 1200';
    final t = Stm32ArmedTelemetry.parse([live]);
    expect(t.isLiveLine, isTrue);
    expect(t.attRollDeg, closeTo(7.0, 0.01));
    expect(t.attPitchDeg, closeTo(-2.0, 0.01));
  });

  test('motor us from ESP UART continuation chunk after LIVE split', () {
    const chunk1 =
        'LIVE | ARMED ang=1 thr%=45 | att r=0.30 p=0.15 y=-101.79 | gyro r=-1.46 p=-1.27 y=-1.07 dps | '
        'set r=0.50 p=-0.20 y=0.00 | out r=-2.00 p=1.50';
    const chunk2 = ' y=0.65 | us=1580 1575 1585 1578';
    final t = Stm32ArmedTelemetry.parse([chunk1, chunk2]);
    expect(t.isLiveLine, isTrue);
    expect(t.motorUs, [1580, 1575, 1585, 1578]);
    expect(t.hasMotors, isTrue);
  });

  test('motor us from ESP UART continuation chunk after DISARMED split', () {
    const chunk1 =
        'DISARMED | ax=0.02 ay=0.01 az=-9.81 |a|=9.81 m/s2 | gx=0.00 gy=0.00 gz=0.00 dps | '
        'mR=0.00 mP=0.00 mY=0.00 | attR=0.12 attP=-0.05 yaw=-102.10 | spR=0.00 spP=0.00 spY=0.00 | '
        'rawA=120 80 -4050 gR=0 0 0 seq=12045 hov=0 mode=stabilize | T=29.50 C P=989.80 hPa | '
        'throttle %=0.00 0.00 0.00 0.00';
    const chunk2 = ' | us=1050 1050 1050 1050 | PID r/p/y=0.00 0.00 0.00';
    final t = Stm32ArmedTelemetry.parse([chunk1, chunk2]);
    expect(t.motorUs, [1050, 1050, 1050, 1050]);
    expect(t.attRollDeg, closeTo(0.12, 0.01));
  });

  test('LIVE att r= chunk without LIVE prefix still parses', () {
    const chunk =
        'att r=0.30 p=0.15 y=-101.79 | gyro r=-1.46 p=-1.27 y=-1.07 dps | '
        'out r=-2.00 p=1.50 y=0.65 | us=1580 1575 1585 1578';
    final t = Stm32ArmedTelemetry.parse([chunk]);
    expect(t.isLiveLine, isTrue);
    expect(t.attRollDeg, closeTo(0.30, 0.01));
    expect(t.hasMotors, isTrue);
  });

  test('merge ESP UART fragments into one LIVE line', () {
    const chunk1 =
        'LIVE | ARMED ang=1 thr%=45 | att r=0.30 p=0.15 y=-101.79 | gyro r=-1.46 p=-1.27 y=-1.07 dps | '
        'set r=0.50 p=-0.20 y=0.00 | out r=-2.00 p=1.50';
    const chunk2 = ' y=0.65 | us=1580 1575 1585 1578';
    // No DISARMED in buffer — simulates debug live flood scrolling poll lines out.
    final t = Stm32ArmedTelemetry.parse([chunk1, chunk2]);
    expect(t.isLiveLine, isTrue);
    expect(t.hasAttitude, isTrue);
    expect(t.attRollDeg, closeTo(0.30, 0.01));
    expect(t.motorUs, [1580, 1575, 1585, 1578]);
  });

  test('bufferContainsMotorField detects us= in raw UART rows', () {
    expect(
      Stm32ArmedTelemetry.bufferContainsMotorField(const [
        'LIVE | ARMED | att r=0 | us=1200 1200 1200 1200',
      ]),
      isTrue,
    );
    expect(
      Stm32ArmedTelemetry.bufferContainsMotorField(const ['OK DISARMED']),
      isFalse,
    );
  });

  test('LIVE motor us wins over newer ARMED poll line with idle us', () {
    const liveHead =
        'LIVE | ARMED ang=1 thr%=45 | att r=0.30 p=0.15 y=-101.79 | gyro r=-1.46 p=-1.27 y=-1.07 dps | '
        'set r=0.50 p=-0.20 y=0.00 | out r=-2.00 p=1.50';
    const liveTail = ' y=0.65 | us=1580 1575 1585 1578';
    const armedTail = ' | us=1050 1050 1050 1050 | PID r/p/y=0.00 0.00 0.00';
    final t = Stm32ArmedTelemetry.parse([liveHead, liveTail, armedTail]);
    expect(t.isLiveLine, isTrue);
    expect(t.motorUs, [1580, 1575, 1585, 1578]);
  });
}
