import 'package:flutter/material.dart';

/// Local light/dark palette for the 3D Attitude tab only.
class Attitude3DTheme {
  const Attitude3DTheme({
    required this.brightness,
    required this.scaffold,
    required this.viewport,
    required this.viewportBorder,
    required this.readoutBar,
    required this.subtitle,
    required this.cellLabel,
    required this.cellValue,
    required this.rawLine,
    required this.grid,
    required this.legendMuted,
    required this.legendBody,
    required this.hubStroke,
    required this.motorStroke,
    required this.toggleBg,
    required this.toggleBorder,
    required this.chipOkBg,
    required this.chipOkBorder,
    required this.chipOkText,
    required this.chipBadBg,
    required this.chipBadBorder,
    required this.chipBadText,
  });

  final Brightness brightness;
  final Color scaffold;
  final Color viewport;
  final Color viewportBorder;
  final Color readoutBar;
  final Color subtitle;
  final Color cellLabel;
  final Color cellValue;
  final Color rawLine;
  final Color grid;
  final Color legendMuted;
  final Color legendBody;
  final Color hubStroke;
  final Color motorStroke;
  final Color toggleBg;
  final Color toggleBorder;
  final Color chipOkBg;
  final Color chipOkBorder;
  final Color chipOkText;
  final Color chipBadBg;
  final Color chipBadBorder;
  final Color chipBadText;

  bool get isLight => brightness == Brightness.light;

  static const dark = Attitude3DTheme(
    brightness: Brightness.dark,
    scaffold: Color(0xFF0C0E10),
    viewport: Color(0xFF141820),
    viewportBorder: Color(0xFF2A3038),
    readoutBar: Color(0xFF101216),
    subtitle: Color(0x73FFFFFF),
    cellLabel: Color(0x73FFFFFF),
    cellValue: Color(0xFFE5E7EB),
    rawLine: Color(0x59FFFFFF),
    grid: Color(0xFF2A3038),
    legendMuted: Color(0xFF9CA3AF),
    legendBody: Color(0xFFE5E7EB),
    hubStroke: Color(0xFF64748B),
    motorStroke: Color(0xFF475569),
    toggleBg: Color(0xFF1A1C1F),
    toggleBorder: Color(0xFF2A3038),
    chipOkBg: Color(0xFF14532D),
    chipOkBorder: Color(0xFF4ADE80),
    chipOkText: Color(0xFF4ADE80),
    chipBadBg: Color(0xFF3F1010),
    chipBadBorder: Color(0xFFEF4444),
    chipBadText: Color(0xFFFCA5A5),
  );

  static const light = Attitude3DTheme(
    brightness: Brightness.light,
    scaffold: Color(0xFFECEFF3),
    viewport: Color(0xFFF8FAFC),
    viewportBorder: Color(0xFFC5CAD1),
    readoutBar: Color(0xFFF0F2F5),
    subtitle: Color(0xFF64748B),
    cellLabel: Color(0xFF64748B),
    cellValue: Color(0xFF1E293B),
    rawLine: Color(0xFF94A3B8),
    grid: Color(0xFFD1D5DB),
    legendMuted: Color(0xFF64748B),
    legendBody: Color(0xFF334155),
    hubStroke: Color(0xFF94A3B8),
    motorStroke: Color(0xFF64748B),
    toggleBg: Color(0xFFFFFFFF),
    toggleBorder: Color(0xFFC5CAD1),
    chipOkBg: Color(0xFFDCFCE7),
    chipOkBorder: Color(0xFF16A34A),
    chipOkText: Color(0xFF15803D),
    chipBadBg: Color(0xFFFEE2E2),
    chipBadBorder: Color(0xFFDC2626),
    chipBadText: Color(0xFFB91C1C),
  );
}
