import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../serial_line_filter.dart';
import '../serial_log_cache.dart';
import '../theme/fc_tune_theme.dart';

/// Embedded STM32 UART log for the FC Tune tab (shared [SerialLogCache]).
class TuneSerialMonitor extends StatefulWidget {
  const TuneSerialMonitor({
    super.key,
    required this.useEsp,
    required this.busy,
    required this.serialCache,
    required this.onClear,
    this.onNotify,
    this.logHeight = 220,
    this.initialProblemsOnly = false,
  });

  final bool useEsp;
  final bool busy;
  final SerialLogCache serialCache;
  final Future<void> Function() onClear;
  final void Function(String message, {bool isError})? onNotify;
  final double logHeight;

  /// Tune bench: default all lines (telemetry + OK). Serial tab defaults to problems.
  final bool initialProblemsOnly;

  @override
  State<TuneSerialMonitor> createState() => _TuneSerialMonitorState();
}

class _TuneSerialMonitorState extends State<TuneSerialMonitor> {
  static const _maxDisplayLines = 300;

  final ScrollController _scroll = ScrollController();
  late bool _problemsOnly = widget.initialProblemsOnly;
  bool _autoScroll = true;
  bool _expanded = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<String> _filtered(List<String> all) {
    if (!_problemsOnly) return all;
    return all.where(SerialLineFilter.shouldShow).toList();
  }

  List<String> _displayLines(List<String> all) {
    final filtered = _filtered(all);
    if (filtered.length <= _maxDisplayLines) return filtered;
    return filtered.sublist(filtered.length - _maxDisplayLines);
  }

  int _hiddenCount(List<String> all) {
    if (!_problemsOnly) return 0;
    return all.length - _filtered(all).length;
  }

  void _toast(String msg, {bool isError = false}) {
    widget.onNotify?.call(msg, isError: isError);
  }

  Future<void> _refresh() async {
    if (!widget.useEsp) return;
    await widget.serialCache.refresh();
  }

  Future<void> _clear() async {
    if (!widget.useEsp || widget.busy) return;
    await widget.onClear();
    await widget.serialCache.refresh();
    _toast('Serial log cleared', isError: false);
  }

  Future<void> _copyAll(List<String> lines) async {
    if (lines.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    _toast('Copied ${lines.length} lines', isError: false);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoScroll && _expanded && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  bool _lineLooksSevere(String line) {
    final lower = line.toLowerCase();
    return lower.contains('error') ||
        lower.contains('fail') ||
        lower.contains('fault') ||
        lower.contains('panic') ||
        lower.contains('hardfault');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return ListenableBuilder(
      listenable: widget.serialCache,
      builder: (context, _) {
        _scrollToEnd();
        final all = widget.serialCache.lines;
        final lines = _displayLines(all);
        final hidden = _hiddenCount(all);

        return DecoratedBox(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SERIAL MONITOR',
                              style: c.labelStyle(
                                fontSize: 9,
                                color: c.accent,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Live STM32 UART · shared with Serial tab',
                              style: c.labelStyle(fontSize: 8, color: c.body),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: c.label,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded) ...[
                Divider(height: 1, color: c.border),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ToolChip(
                        label: _problemsOnly ? 'Problems' : 'All',
                        active: _problemsOnly,
                        onTap: () => setState(() => _problemsOnly = !_problemsOnly),
                      ),
                      _IconTool(
                        icon: Icons.refresh_rounded,
                        tooltip: 'Refresh',
                        onTap: widget.useEsp ? _refresh : null,
                      ),
                      _IconTool(
                        icon: _autoScroll
                            ? Icons.vertical_align_bottom
                            : Icons.pause,
                        tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
                        onTap: () => setState(() => _autoScroll = !_autoScroll),
                      ),
                      _IconTool(
                        icon: Icons.copy_rounded,
                        tooltip: 'Copy',
                        onTap: lines.isEmpty ? null : () => _copyAll(lines),
                      ),
                      _IconTool(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Clear',
                        onTap:
                            widget.useEsp && !widget.busy ? _clear : null,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: widget.logHeight,
                  child: _buildLog(context, lines),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: Text(
                    _statusText(all.length, lines.length, hidden),
                    style: c.labelStyle(fontSize: 7, color: c.label).copyWith(
                      fontFamily: 'monospace',
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _statusText(int total, int shown, int hidden) {
    if (!widget.useEsp) return 'Offline — enable Live ESP on Home';
    if (_problemsOnly) {
      return '$shown shown · $total UART lines'
          '${hidden > 0 ? ' · $hidden hidden' : ''} · poll ~0.9s';
    }
    return '$shown lines · poll ~0.9s (Tune tab)';
  }

  Widget _buildLog(BuildContext context, List<String> lines) {
    final c = context.fc;
    if (!widget.useEsp) {
      return Center(
        child: Text(
          'Enable Live ESP on Home',
          style: c.labelStyle(fontSize: 9, color: c.body),
        ),
      );
    }
    if (lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _problemsOnly
                ? 'No problems in log — tap All for telemetry / OK lines'
                : 'Waiting for STM32 UART…',
            textAlign: TextAlign.center,
            style: c.labelStyle(fontSize: 9, color: c.body).copyWith(height: 1.35),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.cardInset,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Scrollbar(
        controller: _scroll,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(8),
          itemCount: lines.length,
          itemBuilder: (_, i) {
            final line = lines[i];
            final severe = _lineLooksSevere(line);
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: SelectableText(
                line,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  height: 1.35,
                  color: severe ? c.disarm : c.body,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Material(
      color: active ? c.chipFill : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: c.labelStyle(
              fontSize: 8,
              color: active ? c.accent : c.label,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconTool extends StatelessWidget {
  const _IconTool({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      color: onTap != null ? c.body : c.label,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
