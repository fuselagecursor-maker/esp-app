import 'dart:js_interop';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'tello_asset.dart';

/// Web: load GLB bytes → blob URL (dev server 404-safe).
Future<TelloGlbSrc> resolveTelloGlbSrc() async {
  final data = await rootBundle.load(TelloGlbAsset.packagePath);
  final bytes = data.buffer.asUint8List();
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  return TelloGlbSrc(src: url, revokeOnDispose: true);
}

void revokeTelloGlbSrc(TelloGlbSrc? resolved) {
  if (resolved == null || !resolved.revokeOnDispose) return;
  web.URL.revokeObjectURL(resolved.src);
}

class TelloGlbSrc {
  const TelloGlbSrc({required this.src, this.revokeOnDispose = false});

  final String src;
  final bool revokeOnDispose;
}
