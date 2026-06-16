import 'dart:async';

/// Serializes live `rc` HTTP posts so only one request runs at a time and
/// stale completions are ignored after [dispose].
class RcTeleopSender {
  RcTeleopSender({
    required Future<void> Function(String line) post,
    void Function(String message)? onError,
    int maxErrorsBeforeNotify = 8,
  })  : _post = post,
        _onError = onError,
        _maxErrorsBeforeNotify = maxErrorsBeforeNotify;

  final Future<void> Function(String line) _post;
  final void Function(String message)? _onError;
  final int _maxErrorsBeforeNotify;

  String? _pending;
  bool _draining = false;
  bool _disposed = false;
  int _generation = 0;
  int _errorStreak = 0;

  /// Queue latest frame (timer + stick both call this).
  void submit(String command) {
    if (_disposed || command.isEmpty) return;
    _pending = command;
    if (!_draining) {
      scheduleMicrotask(_drain);
    }
  }

  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;

    while (_pending != null && !_disposed) {
      final cmd = _pending!;
      _pending = null;
      final gen = ++_generation;

      try {
        await _post(cmd);
        if (_disposed || gen != _generation) continue;
        _errorStreak = 0;
      } catch (e) {
        if (_disposed || gen != _generation) continue;
        _errorStreak++;
        if (_errorStreak == _maxErrorsBeforeNotify) {
          final msg = _formatError(e);
          if (msg != null) _onError?.call(msg);
          _errorStreak = 0;
        }
      }
    }

    _draining = false;
    if (_pending != null && !_disposed) {
      scheduleMicrotask(_drain);
    }
  }

  /// Timeouts are normal when ESP is busy; only surface hard link failures.
  static String? _formatError(Object e) {
    if (e is TimeoutException) return null;
    final s = e.toString();
    if (s.contains('TimeoutException')) return null;
    if (s.contains('Failed to fetch') || s.contains('ClientException')) {
      return 'RC link lost — check Wi‑Fi to ESP';
    }
    return 'RC error — check connection to ESP';
  }

  /// Stop queue; optionally send one last command (e.g. `rc off`).
  Future<void> dispose({String? finalCommand}) async {
    _disposed = true;
    _pending = null;
    _generation++;
    while (_draining) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    if (finalCommand != null && finalCommand.isNotEmpty) {
      try {
        await _post(finalCommand);
      } catch (_) {
        // Best-effort when leaving Control tab.
      }
    }
  }
}
