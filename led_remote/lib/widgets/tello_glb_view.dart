import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../attitude_3d_motors.dart';
import '../stm32_armed_telemetry.dart';
import '../theme/attitude_3d_theme.dart';
import '../theme/tx_palette.dart';
import '../tello_glb/tello_bridge.dart';
import '../tello_glb/tello_io_engine.dart';
import '../tello_glb/tello_loader.dart';
import '../tello_glb/tello_props.dart';
import 'tello_glb_web_embed_stub.dart'
    if (dart.library.js_interop) 'tello_glb_web_embed.dart';

/// DJI Tello GLB — live attitude + four spinning props from FC motor µs.
class TelloGlbView extends StatefulWidget {
  const TelloGlbView({
    super.key,
    required this.telemetry,
    required this.linkActive,
    required this.theme,
    required this.animTimeSec,
    this.lastUpdate,
    this.demoMode = false,
  });

  final Stm32ArmedTelemetry telemetry;
  final bool linkActive;
  final Attitude3DTheme theme;
  final double animTimeSec;
  final DateTime? lastUpdate;
  final bool demoMode;

  @override
  State<TelloGlbView> createState() => _TelloGlbViewState();
}

class _TelloGlbViewState extends State<TelloGlbView> {
  TelloGlbSrc? _src;
  String? _engineJs;
  String? _loadError;
  WebViewController? _webView;
  String? _initialOrientation;
  String? _lastSyncedOri;
  List<double>? _lastSyncedSpeeds;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  @override
  void dispose() {
    revokeTelloGlbSrc(_src);
    super.dispose();
  }

  Future<void> _loadModel() async {
    try {
      final resolved = await resolveTelloGlbSrc();
      final engineJs = kIsWeb ? null : await loadTelloGlbEngineJs();
      if (!mounted) {
        revokeTelloGlbSrc(resolved);
        return;
      }
      setState(() {
        revokeTelloGlbSrc(_src);
        _src = resolved;
        _engineJs = engineJs;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  @override
  void didUpdateWidget(covariant TelloGlbView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_telemetryChanged(oldWidget)) {
      _syncViewer();
    }
  }

  bool _telemetryChanged(TelloGlbView oldWidget) {
    if (oldWidget.linkActive != widget.linkActive) return true;
    if (oldWidget.demoMode != widget.demoMode) return true;
    final a = oldWidget.telemetry;
    final b = widget.telemetry;
    if (a.rawLine != b.rawLine) return true;
    if (a.isLiveLine != b.isLiveLine) return true;
    if (a.motorUs.length != b.motorUs.length) return true;
    for (var i = 0; i < a.motorUs.length; i++) {
      if (a.motorUs[i] != b.motorUs[i]) return true;
    }
    return !_close(a.attRollDeg, b.attRollDeg) ||
        !_close(a.attPitchDeg, b.attPitchDeg) ||
        !_close(a.yawDeg, b.yawDeg);
  }

  static bool _close(double? a, double? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a - b).abs() < 0.02;
  }

  void _syncViewer() {
    final att = _attitude();
    final speeds = _propSpeeds();
    final ori = TelloGlbProps.orientation(
      rollDeg: att.$1,
      pitchDeg: att.$2,
      yawDeg: att.$3,
    );

    if (_lastSyncedOri == ori &&
        _listEq(_lastSyncedSpeeds, speeds)) {
      return;
    }
    _lastSyncedOri = ori;
    _lastSyncedSpeeds = List<double>.from(speeds);

    if (kIsWeb) {
      telloGlbSetOrientation(ori);
      telloGlbSetPropSpeeds(speeds);
      return;
    }

    final wv = _webView;
    if (wv == null) return;
    wv.runJavaScript(
      'window.telloGlbSetOrientation && window.telloGlbSetOrientation("$ori");',
    );
    wv.runJavaScript(
      'window.telloGlbSetPropSpeeds && window.telloGlbSetPropSpeeds('
      '${speeds[0]}, ${speeds[1]}, ${speeds[2]}, ${speeds[3]});',
    );
  }

  static bool _listEq(List<double>? a, List<double> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.001) return false;
    }
    return true;
  }

  (double, double, double) _attitude() {
    return (
      widget.telemetry.attRollDeg ?? 0.0,
      widget.telemetry.attPitchDeg ?? 0.0,
      widget.telemetry.yawDeg ?? 0.0,
    );
  }

  bool _motorsLive() {
    if (widget.demoMode) return true;
    if (!widget.linkActive) return false;
    if (_isStale()) return false;
    return widget.telemetry.hasMotors;
  }

  List<double> _propSpeeds() {
    if (!_motorsLive()) return const [0, 0, 0, 0];
    return TelloGlbProps.spinRadPerSec(widget.telemetry.motorUs);
  }

  bool _isStale() {
    if (!widget.linkActive) return true;
    final at = widget.lastUpdate;
    if (at == null) return true;
    final limit = widget.telemetry.isLiveLine ? 1200 : 2800;
    return DateTime.now().difference(at).inMilliseconds > limit;
  }

  @override
  Widget build(BuildContext context) {
    final att = _attitude();
    final speeds = _propSpeeds();
    final ori = TelloGlbProps.orientation(
      rollDeg: att.$1,
      pitchDeg: att.$2,
      yawDeg: att.$3,
    );
    _initialOrientation ??= ori;
    final motorUs = Attitude3DMotors.normalizeUs(widget.telemetry.motorUs);
    final spinning = TelloGlbProps.anySpinning(speeds);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_loadError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'GLB load failed.\n$_loadError',
                textAlign: TextAlign.center,
                style: TextStyle(color: widget.theme.legendMuted, fontSize: 12),
              ),
            ),
          )
        else if (_src == null || (!kIsWeb && _engineJs == null))
          Center(
            child: Text(
              'Loading Tello model…',
              style: TextStyle(
                color: widget.theme.legendMuted,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          )
        else if (kIsWeb)
          TelloGlbWebEmbed(
            glbUrl: _src!.src,
            orientation: ori,
            propSpeeds: speeds,
            background: widget.theme.viewport,
          )
        else
          SizedBox.expand(
            child: RepaintBoundary(
              child: ModelViewer(
                key: const ValueKey('tello_glb_mv'),
                src: _src!.src,
                id: TelloGlbProps.modelElementId,
                ar: false,
                autoRotate: false,
                cameraControls: true,
                interactionPrompt: InteractionPrompt.none,
                backgroundColor: widget.theme.viewport,
                orientation: _initialOrientation,
                relatedJs: _engineJs,
                onWebViewCreated: (controller) {
                  _webView = controller;
                  Future<void>.delayed(const Duration(milliseconds: 1200), () {
                    if (mounted) _syncViewer();
                  });
                },
              ),
            ),
          ),
        _Hud(
          theme: widget.theme,
          roll: att.$1,
          pitch: att.$2,
          yaw: att.$3,
          motorUs: motorUs,
          spinning: spinning,
          modelReady: _src != null && _loadError == null,
        ),
      ],
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.theme,
    required this.roll,
    required this.pitch,
    required this.yaw,
    required this.motorUs,
    required this.spinning,
    required this.modelReady,
  });

  final Attitude3DTheme theme;
  final double roll;
  final double pitch;
  final double yaw;
  final List<int> motorUs;
  final bool spinning;
  final bool modelReady;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 8,
      bottom: 8,
      right: 8,
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              modelReady
                  ? (spinning ? 'GLB · props spinning · drag to orbit' : 'GLB · idle props')
                  : 'GLB · loading…',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                letterSpacing: 0.8,
                color: theme.legendMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'R ${roll.toStringAsFixed(1)}°  P ${pitch.toStringAsFixed(1)}°  '
              'Y ${yaw.toStringAsFixed(1)}°',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: TxPalette.amber,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              Attitude3DMotors.formatUsList(motorUs),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                color: theme.legendBody,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
