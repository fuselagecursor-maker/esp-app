import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('telloGlbRegisterHost')
external void _telloGlbRegisterHost(JSAny host);

@JS('telloGlbSetOrientation')
external void _telloGlbSetOrientation(String orientation);

@JS('telloGlbSetPropSpeeds')
external void _telloGlbSetPropSpeeds(
  double s0,
  double s1,
  double s2,
  double s3,
);

void registerTelloGlbHost(web.HTMLElement host) {
  _telloGlbRegisterHost(host as JSAny);
}

void telloGlbSetOrientation(String orientation) {
  _telloGlbSetOrientation(orientation);
}

void telloGlbSetPropSpeeds(List<double> radPerSec) {
  final r = radPerSec.length >= 4
      ? radPerSec
      : [...radPerSec, ...List.filled(4 - radPerSec.length, 0.0)];
  _telloGlbSetPropSpeeds(r[0], r[1], r[2], r[3]);
}
