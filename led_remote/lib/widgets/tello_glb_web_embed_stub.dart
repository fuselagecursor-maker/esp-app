import 'package:flutter/material.dart';

/// Non-web stub — [TelloGlbView] uses [ModelViewer] on mobile/desktop.
class TelloGlbWebEmbed extends StatelessWidget {
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
