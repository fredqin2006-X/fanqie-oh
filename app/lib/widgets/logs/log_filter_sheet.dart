import 'package:flutter/material.dart';

import '../../services/app_log.dart';

class LogFilterSelection {
  const LogFilterSelection({this.level, this.timeWindow});

  final LogLevel? level;
  final Duration? timeWindow;
}

String logTimeWindowLabel(Duration? window) {
  if (window == null) return '不限时间';
  if (window.inMinutes < 60) return '最近 ${window.inMinutes} 分钟';
  return '最近 ${window.inHours} 小时';
}

class LogFilterSheet extends StatefulWidget {
  const LogFilterSheet({super.key, required this.initial});

  final LogFilterSelection initial;

  @override
  State<LogFilterSheet> createState() => _LogFilterSheetState();
}

class _LogFilterSheetState extends State<LogFilterSheet> {
  late LogLevel? _level = widget.initial.level;
  late Duration? _timeWindow = widget.initial.timeWindow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('筛选日志', style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            Text('日志级别', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('全部级别'),
                  selected: _level == null,
                  onSelected: (_) => setState(() => _level = null),
                ),
                for (final level in LogLevel.values)
                  ChoiceChip(
                    label: Text(level.label),
                    selected: _level == level,
                    onSelected: (_) => setState(() => _level = level),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('时间范围', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final window in <Duration?>[
                  null,
                  const Duration(minutes: 5),
                  const Duration(minutes: 30),
                  const Duration(hours: 2),
                ])
                  ChoiceChip(
                    label: Text(logTimeWindowLabel(window)),
                    selected: _timeWindow == window,
                    onSelected: (_) => setState(() => _timeWindow = window),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => setState(() {
                    _level = null;
                    _timeWindow = null;
                  }),
                  child: const Text('重置'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      LogFilterSelection(
                        level: _level,
                        timeWindow: _timeWindow,
                      ),
                    ),
                    child: const Text('应用筛选'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
