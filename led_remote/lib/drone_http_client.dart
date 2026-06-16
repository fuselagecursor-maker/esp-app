import 'dart:convert';

import 'package:http/http.dart' as http;

import 'stm32_reply.dart';

/// Sends text to the ESP **`POST /drone/command`** as form field **`cmd`** (URL-encoded).
///
/// The **ESP firmware** parses the string (see `D:\esp\src\main.cpp` → `executeCommandLine`):
/// - **Several lines** = several commands (non-empty lines only). Response is a **JSON array** if
///   you send multiple lines; a **single JSON object** if you send one line.
/// - Extend **`executeCommandLine()`** on the ESP when you add real motors / flight logic.
///
/// Quick HTTP buttons still use separate GET paths (`/drone/arm`, …); the console is the main
/// extensible path.
class DroneHttpClient {
  DroneHttpClient([String baseUrl = 'http://192.168.4.1']) {
    setBaseUrl(baseUrl);
  }

  final http.Client _client = http.Client();
  final http.Client _liveClient = http.Client();
  String _baseUrl = 'http://192.168.4.1';

  void close() {
    _client.close();
    _liveClient.close();
  }

  void setBaseUrl(String value) {
    _baseUrl = value.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Uri _uri(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$p');
  }

  /// STM32 UART can inject non‑UTF8 bytes; never crash the app on decode.
  static String _responseBody(http.Response res) {
    final text = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
    return text;
  }

  Future<String> _get(String path) async {
    final res = await _client.get(_uri(path)).timeout(const Duration(seconds: 8));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('$path → HTTP ${res.statusCode}');
    }
    final body = _responseBody(res);
    return body.isEmpty ? 'OK' : body;
  }

  /// Same path as command console — sends exact STM32 phrase + newline via ESP UART.
  Future<String> arm() => sendCommandLine('arm');

  Future<String> disarm() => sendCommandLine('disarm');

  Future<String> testArm() => sendCommandLine('test arm');

  Future<String> moveForward() => _get('/drone/move_forward');

  Future<String> moveBack() => _get('/drone/move_back');

  /// Full multi-line script; ESP runs **one command per line**.
  Future<String> sendCommandLine(
    String line, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final res = await _client
        .post(
          _uri('/drone/command'),
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          },
          body: 'cmd=${Uri.encodeQueryComponent(line)}',
        )
        .timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('/drone/command → HTTP ${res.statusCode} ${_responseBody(res)}');
    }
    final body = _responseBody(res);
    return body.isEmpty ? 'OK' : body;
  }

  /// ESC cal ~12 s, IMU ~3 s — longer HTTP + ESP UART wait.
  Future<String> sendCalibrationCommand(String line) {
    final lower = line.trim().toLowerCase();
    final esc = lower == 'cal esc' ||
        lower == 'calibrate' ||
        lower == 'escal';
    return sendCommandLine(
      line,
      timeout: Duration(seconds: esc ? 28 : 14),
    );
  }

  Future<String> calEsc() => sendCalibrationCommand('cal esc');

  Future<String> calibrate() => sendCalibrationCommand('calibrate');

  Future<String> escal() => sendCalibrationCommand('escal');

  Future<String> calImu() => sendCalibrationCommand('cal imu');

  Future<String> calHelp() => sendCommandLine('cal help');

  /// STM32 UART ring buffer on ESP (`GET /drone/serial`). Retries on Wi‑Fi glitches.
  Future<List<String>> fetchStm32SerialLog() async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await _client
            .get(_uri('/drone/serial'))
            .timeout(const Duration(seconds: 5));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('/drone/serial → HTTP ${res.statusCode}');
        }
        return Stm32Reply.parseSerialLines(_responseBody(res));
      } catch (e) {
        lastError = e;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
        }
      }
    }
    throw lastError ?? Exception('serial fetch failed');
  }

  Future<void> clearStm32SerialLog() async {
    final res = await _client
        .post(_uri('/drone/serial/clear'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('/drone/serial/clear → HTTP ${res.statusCode}');
    }
  }

  static const _killTimeout = Duration(milliseconds: 320);

  /// `rc off` with a short timeout — safe for background / tab switches.
  Future<void> sendRcOffBestEffort() async {
    try {
      await sendCommandLive('rc off').timeout(_killTimeout);
    } catch (_) {}
  }

  /// Disarm without blocking the UI for the full STM32 wait.
  Future<void> sendDisarmBestEffort() async {
    try {
      await sendCommandLive('disarm').timeout(_killTimeout);
    } catch (_) {
      try {
        await sendCommandLine(
          'disarm',
          timeout: const Duration(milliseconds: 800),
        );
      } catch (_) {}
    }
  }

  /// Emergency stop: parallel live UART lines, no sequential wait, no STM32 ACK.
  void sendKillInstant() {
    for (final line in const [
      'rc off',
      'throttle 0',
      'rc 0 0 0 0',
      'disarm',
    ]) {
      _sendKillLine(line);
    }
  }

  void _sendKillLine(String line) {
    _liveClient
        .post(
          _uri('/drone/command'),
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          },
          body: 'cmd=${Uri.encodeQueryComponent(line)}',
        )
        .timeout(_killTimeout)
        .then((_) {}, onError: (_) {});
  }

  /// Low-latency teleop (single line). ESP forwards without waiting for STM32 reply.
  Future<void> sendCommandLive(String line) async {
    final res = await _liveClient
        .post(
          _uri('/drone/command'),
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          },
          body: 'cmd=${Uri.encodeQueryComponent(line)}',
        )
        .timeout(const Duration(milliseconds: 800));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('live → HTTP ${res.statusCode}');
    }
  }

  /// Several live lines in one POST (throttle + rc @ 40 Hz).
  Future<void> sendTeleopLive(String multiline) async {
    final res = await _liveClient
        .post(
          _uri('/drone/command'),
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          },
          body: 'cmd=${Uri.encodeQueryComponent(multiline)}',
        )
        .timeout(const Duration(milliseconds: 800));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('teleop → HTTP ${res.statusCode}');
    }
  }
}
