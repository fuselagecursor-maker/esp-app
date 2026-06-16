import 'dart:convert';

import 'package:http/http.dart' as http;

/// Controls LED state. [MockLedBackend] is for testing the UI without an ESP.
/// [EspHttpLedBackend] talks to the firmware over HTTP (Wi‑Fi on ESP later).
abstract class LedBackend {
  Future<bool> readState();
  Future<bool> toggle();
}

class MockLedBackend implements LedBackend {
  bool _on = false;

  @override
  Future<bool> readState() async => _on;

  @override
  Future<bool> toggle() async {
    _on = !_on;
    return _on;
  }
}

/// Expects GET [baseUrl/led/toggle] → toggles firmware LED and optional JSON body {"on":true}.
/// Optional GET [baseUrl/led/status] → {"on":true|false}.
class EspHttpLedBackend implements LedBackend {
  EspHttpLedBackend(this._baseUrl);

  String _baseUrl;

  void setBaseUrl(String value) {
    _baseUrl = value.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Uri _uri(String path) {
    final base = _baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  bool _parseOn(String body) {
    final t = body.trim();
    if (t.isEmpty) return false;
    try {
      final m = jsonDecode(t);
      if (m is Map && m['on'] is bool) return m['on'] as bool;
    } catch (_) {}
    return t.toUpperCase().contains('TRUE') || t.toUpperCase().contains('"ON"');
  }

  @override
  Future<bool> readState() async {
    final res = await http.get(_uri('/led/status')).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception('status HTTP ${res.statusCode}');
    }
    return _parseOn(res.body);
  }

  @override
  Future<bool> toggle() async {
    final res = await http.get(_uri('/led/toggle')).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception('toggle HTTP ${res.statusCode}');
    }
    return _parseOn(res.body);
  }
}
