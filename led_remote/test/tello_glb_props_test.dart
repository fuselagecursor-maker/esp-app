import 'package:flutter_test/flutter_test.dart';
import 'package:led_remote/tello_glb/tello_props.dart';

void main() {
  test('orientation negates FC pitch and corrects GLB +X nose to +Z front', () {
    expect(
      TelloGlbProps.orientation(rollDeg: 10, pitchDeg: 5, yawDeg: 90),
      '10.00deg -5.00deg 0.00deg',
    );
    expect(
      TelloGlbProps.orientation(rollDeg: 0, pitchDeg: 0, yawDeg: 0),
      '0.00deg -0.00deg -90.00deg',
    );
  });

  test('spin rates follow motor us', () {
    final rates = TelloGlbProps.spinRadPerSec([1750, 1750, 1750, 1750]);
    expect(TelloGlbProps.anySpinning(rates), isTrue);
    expect(rates.every((r) => r.abs() > 0), isTrue);
  });

  test('idle motors do not spin', () {
    final rates = TelloGlbProps.spinRadPerSec([1000, 1000, 1000, 1000]);
    expect(TelloGlbProps.anySpinning(rates), isFalse);
  });
}
