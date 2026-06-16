import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

String? _cachedEngineJs;

/// Load prop-spin engine for embedding in model-viewer HTML (`relatedJs`).
Future<String> loadTelloGlbEngineJs() async {
  return _cachedEngineJs ??=
      await rootBundle.loadString('web/tello_glb_engine.js');
}

/// Legacy inject — page navigation clears JS injected before [loadRequest].
@Deprecated('Use loadTelloGlbEngineJs + ModelViewer.relatedJs instead')
Future<void> installTelloGlbEngine(WebViewController controller) async {
  final js = await loadTelloGlbEngineJs();
  await controller.runJavaScript(js);
}
