/// Filters STM32 UART log lines for the Serial tab "problems only" view.
abstract final class SerialLineFilter {
  /// Default for Serial monitor UI.
  static bool shouldShow(String line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    if (_isPromptOnly(t)) return false;
    if (_isRoutineTelemetry(t)) return false;
    if (_isRoutineRcLine(t)) return false;
    if (_isRoutineOkAck(t)) return false;

    return _hasProblemSignal(t);
  }

  static bool _isPromptOnly(String t) =>
      t == '>' || t == '>>' || RegExp(r'^>+\s*$').hasMatch(t);

  static bool _isRoutineRcLine(String t) {
    final lower = t.toLowerCase();
    return RegExp(r'^rc\s+\d+\s+-?\d+\s+-?\d+\s+-?\d+\s*$').hasMatch(lower) ||
        lower == 'rc off';
  }

  static bool _isRoutineTelemetry(String t) {
    final lower = t.toLowerCase();
    if (RegExp(r'^(spp|spr|spy|roll|pitch|yaw|thr|lat|lon)[:\s=]', caseSensitive: false)
        .hasMatch(lower)) {
      return true;
    }
    if (RegExp(
      r'\b(spp|spr|spy)\b.*\b(roll|pitch|yaw|thr)\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    return false;
  }

  static bool _isRoutineOkAck(String t) {
    final lower = t.toLowerCase();
    if (!lower.startsWith('ok')) return false;
    if (_hasProblemSignal(t)) return false;
    return RegExp(
      r'^ok\s*(armed|disarmed|imu|esc|cal|throttle|rc)?',
      caseSensitive: false,
    ).hasMatch(lower) ||
        lower.contains('cal done') ||
        lower.contains('calibrated') ||
        lower == 'ok';
  }

  static bool _hasProblemSignal(String t) {
    final lower = t.toLowerCase();

    const keywords = [
      'error',
      'err:',
      'fail',
      'fault',
      'invalid',
      'unknown',
      'timeout',
      'timed out',
      'reject',
      'denied',
      'abort',
      'panic',
      'hardfault',
      'hard fault',
      'assert',
      'warning',
      'warn:',
      'no_stm32',
      'no stm32',
      'no reply',
      'not ok',
      'nack',
      'uart',
      'overrun',
      'overflow',
      'underflow',
      'out of range',
      'not armed',
      'cannot',
      "can't",
      'unable',
      'refused',
      'unexpected',
      'illegal',
      'bad ',
      'missing',
    ];

    for (final k in keywords) {
      if (lower.contains(k)) return true;
    }

    if (lower.contains('"ok":false') || lower.contains("'ok':false")) {
      return true;
    }
    if (RegExp(r'\bnot\s+ok\b', caseSensitive: false).hasMatch(lower)) {
      return true;
    }

    // STM32 help / error list lines often start with ?
    if (t.startsWith('?') || lower.startsWith('unknown command')) {
      return true;
    }

    return false;
  }
}
