import 'package:flutter/material.dart';

/// Local light/dark palette for the FC Tune tab only.
class FcTuneColors {
  const FcTuneColors({
    required this.scaffold,
    required this.card,
    required this.cardInset,
    required this.border,
    required this.track,
    required this.accent,
    required this.label,
    required this.body,
    required this.value,
    required this.arm,
    required this.disarm,
    required this.thumb,
    required this.iconButtonBg,
    required this.chipFill,
    required this.armTrack,
    required this.armBorder,
    required this.armGuard,
    required this.armLever,
    required this.armLeverBusy,
    required this.onAccent,
    required this.brightness,
  });

  final Color scaffold;
  final Color card;
  final Color cardInset;
  final Color border;
  final Color track;
  final Color accent;
  final Color label;
  final Color body;
  final Color value;
  final Color arm;
  final Color disarm;
  final Color thumb;
  final Color iconButtonBg;
  final Color chipFill;
  final Color armTrack;
  final Color armBorder;
  final Color armGuard;
  final Color armLever;
  final Color armLeverBusy;
  final Color onAccent;
  final Brightness brightness;

  bool get isLight => brightness == Brightness.light;

  static const dark = FcTuneColors(
    scaffold: Color(0xFF202326),
    card: Color(0xFF1A1C1F),
    cardInset: Color(0xFF181A1C),
    border: Color(0xFF2A2820),
    track: Color(0xFF1E2024),
    accent: Color(0xFFC07010),
    label: Color(0xFF5A5040),
    body: Color(0xFF7A7468),
    value: Color(0xFFC07010),
    arm: Color(0xFF20C840),
    disarm: Color(0xFFC03030),
    thumb: Color(0xFF6A7078),
    iconButtonBg: Color(0xFF1E2024),
    chipFill: Color(0xFF141618),
    armTrack: Color(0xFF1E2024),
    armBorder: Color(0xFF2A2820),
    armGuard: Color(0xFF35393D),
    armLever: Color(0xFF2A2E32),
    armLeverBusy: Color(0xFF3A3E42),
    onAccent: Colors.black,
    brightness: Brightness.dark,
  );

  static const light = FcTuneColors(
    scaffold: Color(0xFFECEFF3),
    card: Color(0xFFFFFFFF),
    cardInset: Color(0xFFF5F6F8),
    border: Color(0xFFC5CAD1),
    track: Color(0xFFD8DDE4),
    accent: Color(0xFFB85C08),
    label: Color(0xFF5C564E),
    body: Color(0xFF3D3935),
    value: Color(0xFF9A4E06),
    arm: Color(0xFF168832),
    disarm: Color(0xFFC03030),
    thumb: Color(0xFF7A828C),
    iconButtonBg: Color(0xFFE4E8ED),
    chipFill: Color(0xFFF0F2F5),
    armTrack: Color(0xFFD8DDE4),
    armBorder: Color(0xFFB8BFC8),
    armGuard: Color(0xFFC5CAD1),
    armLever: Color(0xFFE2E6EB),
    armLeverBusy: Color(0xFFCDD2D9),
    onAccent: Colors.white,
    brightness: Brightness.light,
  );

  TextStyle labelStyle({double fontSize = 8, Color? color, double? letterSpacing}) =>
      TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize,
        letterSpacing: letterSpacing ?? 2,
        color: color ?? label,
        fontWeight: FontWeight.w500,
      );

  ThemeData materialTheme() {
    final base = brightness == Brightness.light ? ThemeData.light() : ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      cardColor: card,
      dividerColor: border,
      colorScheme: base.colorScheme.copyWith(
        brightness: brightness,
        primary: accent,
        surface: card,
        onSurface: body,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: track,
        thumbColor: thumb,
        trackHeight: 5,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return arm;
          return thumb;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return arm.withValues(alpha: 0.45);
          }
          return track;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: track,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
    );
  }
}

class FcTuneTheme extends InheritedWidget {
  const FcTuneTheme({
    super.key,
    required this.colors,
    required super.child,
  });

  final FcTuneColors colors;

  static FcTuneColors of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FcTuneTheme>();
    assert(scope != null, 'FcTuneTheme not found');
    return scope!.colors;
  }

  @override
  bool updateShouldNotify(FcTuneTheme oldWidget) => colors != oldWidget.colors;
}

extension FcTuneBuildContext on BuildContext {
  FcTuneColors get fc => FcTuneTheme.of(this);
}
