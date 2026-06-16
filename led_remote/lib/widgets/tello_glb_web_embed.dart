import 'dart:js_interop';

import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../tello_glb/tello_bridge.dart';
import '../tello_glb/tello_props.dart';

/// Flutter web: embed `<model-viewer>` via platform view (innerHTML).
class TelloGlbWebEmbed extends StatefulWidget {
  const TelloGlbWebEmbed({
    super.key,
    required this.glbUrl,
    required this.orientation,
    required this.propSpeeds,
    required this.background,
  });

  final String glbUrl;
  final String orientation;
  final List<double> propSpeeds;
  final Color background;

  @override
  State<TelloGlbWebEmbed> createState() => _TelloGlbWebEmbedState();
}

class _TelloGlbWebEmbedState extends State<TelloGlbWebEmbed> {
  late final String _viewType =
      'tello-glb-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _registerFactory();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushState());
  }

  @override
  void didUpdateWidget(covariant TelloGlbWebEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pushState();
  }

  void _pushState() {
    telloGlbSetOrientation(widget.orientation);
    telloGlbSetPropSpeeds(widget.propSpeeds);
  }

  void _registerFactory() {
    final bg = widget.background;
    final src = widget.glbUrl;
    final speeds = TelloGlbProps.speedsCsv(widget.propSpeeds);
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final host = web.HTMLDivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden'
        ..style.backgroundColor =
            'rgba(${(bg.r * 255).round()}, ${(bg.g * 255).round()}, ${(bg.b * 255).round()}, ${bg.a})';

      final html = '''
<model-viewer
  id="${TelloGlbProps.modelElementId}"
  src="$src"
  camera-controls
  touch-action="pan-y"
  interaction-prompt="none"
  shadow-intensity="0.85"
  exposure="1.05"
  environment-image="neutral"
  orientation="${widget.orientation}"
  style="width:100%;height:100%;background:transparent;"
  data-prop-speeds="$speeds"
></model-viewer>''';
      host.innerHTML = html.toJS;

      registerTelloGlbHost(host);
      return host;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return HtmlElementView(viewType: _viewType);
  }
}
