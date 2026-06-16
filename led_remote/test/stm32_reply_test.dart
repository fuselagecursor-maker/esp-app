import 'package:flutter_test/flutter_test.dart';
import 'package:led_remote/stm32_reply.dart';

void main() {
  test('tuneCommandOk accepts ESP live throttle forward', () {
    const body =
        '{"ok":true,"live":true,"forwarded":"throttle 45"}';
    expect(Stm32Reply.tuneCommandOk(body), isTrue);
  });

  test('tuneCommandOk accepts blocking pid OK', () {
    const body =
        '{"ok":true,"stm32_ok":true,"stm32_replied":true,"stm32":"OK pid rate roll 1.2 0 0.008\\r\\n"}';
    expect(Stm32Reply.tuneCommandOk(body), isTrue);
  });
}
