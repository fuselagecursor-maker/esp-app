import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_toast.dart';
import 'serial_line_filter.dart';
import 'serial_log_cache.dart';
import 'widgets/app_motion.dart';

/// Live STM32 UART log via shared [SerialLogCache] (one ESP poll for whole app).
class SerialMonitorPage extends StatefulWidget {
  const SerialMonitorPage({
    super.key,
    required this.useEsp,
    required this.busy,
    required this.serialCache,
    required this.clearLog,
    required this.onConnect,
  });

  final bool useEsp;
  final bool busy;
  final SerialLogCache serialCache;
  final Future<void> Function() clearLog;
  final Future<bool> Function() onConnect;

  @override
  State<SerialMonitorPage> createState() => _SerialMonitorPageState();
}

class _SerialMonitorPageState extends State<SerialMonitorPage> {
  static const _maxDisplayLines = 400;

  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;
  bool _problemsOnly = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<String> _filtered(List<String> all) {
    if (!_problemsOnly) return all;
    return all.where(SerialLineFilter.shouldShow).toList();
  }

  List<String> get _displayLines {
    final filtered = _filtered(widget.serialCache.lines);
    if (filtered.length <= _maxDisplayLines) return filtered;
    return filtered.sublist(filtered.length - _maxDisplayLines);
  }

  int get _hiddenCount {
    if (!_problemsOnly) return 0;
    final all = widget.serialCache.lines;
    return all.length - _filtered(all).length;
  }

  Future<void> _refresh() async {
    if (!widget.useEsp) return;
    await widget.serialCache.refresh();
  }

  Future<void> _clear() async {
    await widget.clearLog();
    await widget.serialCache.refresh();
    if (mounted) {
      AppToast.show(context, 'Log cleared', isError: false, isSuccess: true);
    }
  }

  Future<void> _copyAll() async {
    final lines = _displayLines;
    if (lines.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      AppToast.show(context, 'Copied serial log', isError: false, isSuccess: true);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoScroll && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.serialCache,
      builder: (context, _) {
        _scrollToEnd();
        final lines = _displayLines;
        return Scaffold(
          backgroundColor: const Color(0xFF1A1D21),
          appBar: AppBar(
            backgroundColor: const Color(0xFF252A30),
            foregroundColor: const Color(0xFFE8E4DC),
            title: const Text('STM32 Serial'),
            actions: [
              TextButton.icon(
                onPressed: () => setState(() => _problemsOnly = !_problemsOnly),
                icon: Icon(
                  _problemsOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
                  size: 18,
                ),
                label: Text(
                  _problemsOnly ? 'Problems' : 'All',
                  style: const TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: _problemsOnly
                      ? const Color(0xFFE8941A)
                      : const Color(0xFF8A8580),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: widget.useEsp ? _refresh : null,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
                onPressed: () => setState(() => _autoScroll = !_autoScroll),
                icon: Icon(
                  _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                onPressed: lines.isEmpty ? null : _copyAll,
                icon: const Icon(Icons.copy_rounded),
              ),
              IconButton(
                tooltip: 'Clear',
                onPressed: widget.busy || !widget.useEsp ? null : _clear,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ActivityIndicatorBar(
                active: widget.useEsp,
                color: const Color(0xFFE8941A),
              ),
              if (!widget.useEsp) _buildConnectBanner(),
              Expanded(child: _buildLog(lines)),
              _buildStatusBar(lines.length),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConnectBanner() {
    return Material(
      color: const Color(0xFF3A2020),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Live ESP off — enable on Home or connect below.',
                style: TextStyle(color: Color(0xFFE8E4DC), fontSize: 13),
              ),
            ),
            FilledButton(
              onPressed: widget.busy
                  ? null
                  : () async {
                      await widget.onConnect();
                    },
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLog(List<String> lines) {
    if (!widget.useEsp) {
      return const Center(
        child: Text(
          'Enable Live ESP on Home',
          style: TextStyle(color: Color(0xFF8A8580)),
        ),
      );
    }
    if (lines.isEmpty) {
      return Center(
        child: Text(
          _problemsOnly
              ? 'No problems in log — OK / telemetry hidden.\n'
                  'Tap “All” to see everything.'
              : 'Waiting for STM32 UART…',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8A8580), height: 1.4),
        ),
      );
    }
    return Scrollbar(
      controller: _scroll,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        itemCount: lines.length,
        itemBuilder: (_, i) {
          final line = lines[i];
          final warn = _lineLooksSevere(line);
          return SerialLogLine(
            index: i,
            total: lines.length,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: SelectableText(
                line,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.35,
                  color: warn
                      ? const Color(0xFFFF8A7A)
                      : const Color(0xFFE8C070),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _lineLooksSevere(String line) {
    final lower = line.toLowerCase();
    return lower.contains('error') ||
        lower.contains('fail') ||
        lower.contains('fault') ||
        lower.contains('panic') ||
        lower.contains('hardfault');
  }

  Widget _buildStatusBar(int count) {
    final total = widget.serialCache.lines.length;
    String status;
    if (!widget.useEsp) {
      status = 'Offline';
    } else if (_problemsOnly) {
      status = '$count problem${count == 1 ? '' : 's'}'
          ' · $total UART lines'
          '${_hiddenCount > 0 ? ' · $_hiddenCount hidden' : ''}'
          ' · poll ~1.3s';
    } else {
      status = '$count lines · shared poll ~1.3s';
    }

    return Material(
      color: const Color(0xFF121416),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: AnimatedMetricText(
          value: status,
          style: const TextStyle(
            color: Color(0xFF6A6560),
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
