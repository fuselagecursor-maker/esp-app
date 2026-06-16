import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Subtle beeps for the arm lever: one tone armed, two tones disarmed.
class ArmAudio {
  ArmAudio._();

  static final ArmAudio instance = ArmAudio._();

  final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  bool _ready = false;

  Future<void> ensureReady() async {
    if (_ready) return;
    await _player.setVolume(0.28);
    _ready = true;
  }

  Future<void> armed() async {
    await ensureReady();
    await _playTone(frequencyHz: 880, durationMs: 70);
  }

  Future<void> disarmed() async {
    await ensureReady();
    await _playTone(frequencyHz: 620, durationMs: 65);
    await Future<void>.delayed(const Duration(milliseconds: 85));
    await _playTone(frequencyHz: 620, durationMs: 65);
  }

  Future<void> _playTone({
    required double frequencyHz,
    required int durationMs,
  }) async {
    try {
      final wav = _wavTone(
        frequencyHz: frequencyHz,
        durationMs: durationMs,
        volume: 0.22,
      );
      await _player.stop();
      await _player.play(BytesSource(wav));
      // Avoid onPlayerComplete.first — rapid arm/disarm can leave a stale future.
      await Future<void>.delayed(
        Duration(milliseconds: durationMs + 40),
      );
    } catch (_) {
      // Ignore if audio is unavailable (e.g. silent mode / web block).
    }
  }

  /// Minimal mono 8-bit WAV (quiet, short beep).
  static Uint8List _wavTone({
    required double frequencyHz,
    required int durationMs,
    required double volume,
  }) {
    const sampleRate = 22050;
    final sampleCount = (sampleRate * durationMs / 1000).round().clamp(1, 4096);
    final dataLen = sampleCount;
    final out = Uint8List(44 + dataLen);
    final view = ByteData.sublistView(out);

    void writeStr(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        out[offset + i] = s.codeUnitAt(i);
      }
    }

    writeStr(0, 'RIFF');
    view.setUint32(4, 36 + dataLen, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, 1, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate, Endian.little);
    view.setUint16(32, 1, Endian.little);
    view.setUint16(34, 8, Endian.little);
    writeStr(36, 'data');
    view.setUint32(40, dataLen, Endian.little);

    final peak = (127 * volume).round().clamp(8, 80);
    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final attack = (t * 120).clamp(0.0, 1.0);
      final release =
          ((durationMs / 1000 - t) * 120).clamp(0.0, 1.0);
      final env = math.min(attack, release);
      final wave = math.sin(2 * math.pi * frequencyHz * t);
      final sample = (128 + peak * wave * env).round().clamp(0, 255);
      out[44 + i] = sample;
    }

    return out;
  }
}
