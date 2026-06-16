import 'package:flutter/material.dart';

export 'tx_palette.dart';

import 'tx_palette.dart';

/// Side rail / legacy references.
abstract final class FrSkyPalette {
  static const bodyDark = TxPalette.panel;
  static const bodyCharcoal = TxPalette.panelDeep;
  static const faceplate = TxPalette.panel;
  static const faceplateHi = TxPalette.panel;
  static const faceplateShadow = TxPalette.panelDeep;
  static const bronze = TxPalette.amber;
  static const bronzeHi = TxPalette.amber;
  static const bronzeRing = TxPalette.amber;
  static const silver = Color(0xFF8A9098);
  static const silverHi = Color(0xFFA8B0B8);
  static const label = Color(0xFF9A9590);
  static const labelDim = TxPalette.labelMuted;
  static const armGreen = TxPalette.armLed;
  static const disarmRed = Color(0xFF804040);
  static const gimbalWell = TxPalette.recess;
  static const screenBg = TxPalette.statusBg;
  static const screenLine = TxPalette.amber;
}
