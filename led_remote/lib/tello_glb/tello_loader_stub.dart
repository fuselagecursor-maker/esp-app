import 'tello_asset.dart';

/// Mobile/desktop: [ModelViewer] serves the Flutter asset path directly.
Future<TelloGlbSrc> resolveTelloGlbSrc() async {
  return TelloGlbSrc(src: TelloGlbAsset.packagePath);
}

void revokeTelloGlbSrc(TelloGlbSrc? resolved) {}

class TelloGlbSrc {
  const TelloGlbSrc({required this.src, this.revokeOnDispose = false});

  final String src;
  final bool revokeOnDispose;
}
