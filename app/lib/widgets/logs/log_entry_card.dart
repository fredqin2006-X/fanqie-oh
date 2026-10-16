import 'package:flutter/material.dart';

import '../../services/app_log.dart';

/// Collapsed summaries keep stack traces from taking over the log list.
class LogEntryCard extends StatefulWidget {
  const LogEntryCard({super.key, required this.entry, required this.onCopy});

  final LogEntry entry;
  final VoidCallback onCopy;

  @override
  State<LogEntryCard> createState() => _LogEntryCardState();
}

class _LogEntryCardState extends State<LogEntryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = switch (entry.level) {
      LogLevel.debug => colors.onSurfaceVariant,
      LogLevel.info => colors.tertiary,
      LogLevel.warn =>
        theme.brightness == Brightness.dark
            ? const Color(0xFFFFCF7C)
            : const Color(0xFF805300),
      LogLevel.error => colors.error,
    };
    final time = entry.time.toLocal();
    final timestamp = time.toIso8601String();
    final messageStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      height: 1.5,
      color: colors.onSurface,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            entry.level.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.tag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timestamp.substring(11, 19),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                    if (!_expanded) ...[
                      const SizedBox(height: 8),
                      Text(
                        entry.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: messageStyle,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    '${timestamp.replaceFirst('T', ' ')} · ${entry.tag}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(entry.message, style: messageStyle),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: widget.onCopy,
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('复制单条'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
