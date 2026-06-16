import 'package:flutter/material.dart';

bool isLandscape(BuildContext context) =>
    MediaQuery.orientationOf(context) == Orientation.landscape;

/// Max width for centered phone UI in portrait; wider cap in landscape.
double contentMaxWidth(BuildContext context) {
  if (isLandscape(context)) {
    return MediaQuery.sizeOf(context).width;
  }
  return 480;
}

EdgeInsets pagePadding(BuildContext context) {
  final land = isLandscape(context);
  return EdgeInsets.fromLTRB(land ? 12 : 20, land ? 4 : 8, land ? 12 : 20, land ? 8 : 28);
}
