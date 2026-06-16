import 'dart:convert';

/// Parse ESP JSON replies from `/drone/command` (STM32 UART bridge).
abstract final class Stm32Reply {
  static bool calComplete(String body, {required bool esc}) {
    final lower = body.toLowerCase();
    if (lower.contains('"cal_complete":true')) return true;
    if (esc) {
      return lower.contains('esc cal done');
    }
    return lower.contains('imu cal done') ||
        lower.contains('imu calibrated') ||
        lower.contains('ok imu cal') ||
        lower.contains('imu cal ok');
  }

  static bool noStm32Reply(String body) =>
      body.contains('no_stm32_reply') || body.contains('"stm32_replied":false');

  static bool espFailed(String body) => body.contains('"ok":false');

  /// Arm / disarm / custom commands that expect an STM32 acknowledgement.
  static bool commandAccepted(String body) => tuneCommandOk(body);

  /// Tune tab + Home: accept blocking UART replies and ESP live-forward path.
  ///
  /// ESP routes `throttle N` through [forwardStm32Live] — JSON has `"live":true`
  /// but no `"stm32_ok":true` even when the line was sent.
  static bool tuneCommandOk(String body) {
    final lower = body.toLowerCase();
    if (espFailed(body)) return false;
    if (lower.contains('"stm32_ok":true')) return true;
    if (lower.contains('"live":true') && lower.contains('"ok":true')) {
      return true;
    }
    final stm32 = stm32Text(body)?.toLowerCase() ?? '';
    if (stm32.contains('ok throttle') ||
        stm32.contains('ok pid') ||
        stm32.contains('ok filter') ||
        stm32.contains('ok hover') ||
        stm32.contains('ok stabilize') ||
        stm32.contains('ok armmax') ||
        stm32.contains('ok armed') ||
        stm32.contains('ok disarmed') ||
        stm32.contains('disarmed')) {
      return true;
    }
    if (lower.contains('ok armed') || lower.contains('"armed"')) return true;
    if (lower.contains('disarmed')) return true;
    return false;
  }

  static List<String> parseSerialLines(String body) {
    try {
      final data = jsonDecode(body.trim());
      if (data is! Map<String, dynamic>) return const [];
      final raw = data['lines'];
      if (raw is! List) return const [];
      return raw.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  static String? forwardedCmd(String body) {
    final m = RegExp(r'"forwarded":"((?:\\.|[^"\\])*)"').firstMatch(body);
    if (m == null) return null;
    return m.group(1)?.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  }

  /// Unescape the `"stm32":"..."` field from ESP JSON.
  static String? stm32Text(String body) {
    const key = '"stm32":"';
    final start = body.indexOf(key);
    if (start < 0) return null;
    final buf = StringBuffer();
    for (var i = start + key.length; i < body.length; i++) {
      final c = body[i];
      if (c == '\\' && i + 1 < body.length) {
        final n = body[i + 1];
        if (n == 'n') {
          buf.write('\n');
          i++;
          continue;
        }
        if (n == 'r') {
          buf.write('\r');
          i++;
          continue;
        }
        if (n == '\\' || n == '"') {
          buf.write(n);
          i++;
          continue;
        }
      }
      if (c == '"') break;
      buf.write(c);
    }
    final s = buf.toString().trim();
    return s.isEmpty ? null : s;
  }
}
