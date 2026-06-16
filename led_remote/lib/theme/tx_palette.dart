import 'package:flutter/material.dart';

/// Machined aluminum RC transmitter — no neon, minimal glow (ARM LED only).
abstract final class TxPalette {
  static const panel = Color(0xFF202326);
  static const panelDeep = Color(0xFF1A1C1F);
  static const amber = Color(0xFFC07010);
  static const armLed = Color(0xFF20C840);
  static const labelMuted = Color(0xFF5A5040);
  static const engraved = Color(0xFF2A2820);
  static const recess = Color(0xFF141618);
  static const matteCap = Color(0xFF181A1C);
  static const track = Color(0xFF1E2024);
  static const rivetBody = Color(0xFF3A3E42);
  static const rivetHi = Color(0xFF7A8088);
  static const statusBg = Color(0xFF080808);
  static const ledOff = Color(0xFF2A2820);

  static const labelStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 8,
    letterSpacing: 2,
    color: labelMuted,
    fontWeight: FontWeight.w500,
  );
}
