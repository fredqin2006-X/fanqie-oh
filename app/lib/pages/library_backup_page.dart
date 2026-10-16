import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/library_backup.dart';
import '../services/library_backup_service.dart';
import '../widgets/home/home_design.dart';

class LibraryBackupPage extends StatefulWidget {
  const LibraryBackupPage({super.key});

  @override
  State<LibraryBackupPage> createState() => _LibraryBackupPageState();
}

class _LibraryBackupPageState extends State<LibraryBackupPage> {
  final _service = LibraryBackupService();
  LibraryBackup? _preview;
  String? _busy;
  String? _message;

  Future<void> _run(
    String label,
    Future<void> Function() action, {
    bool restoring = false,
  }) async {
    if (_busy != null) return;
    setState(() {
      _busy = label;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = restoring
            ? '恢复未完成，部分记录可能已写入。可重试同一文件，已存在的数据会保留。'
            : switch (error) {
                FormatException() => error.message,
                PlatformException() => error.message ?? '文件操作失败，请重试',
                MissingPluginException() => '当前运行环境不支持系统文件选择器',
                _ => '无法完成操作，请确认本机数据已加载、存储空间充足后重试',
              };
      });
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _export() => _run('正在导出，请在系统窗口选择保存位置…', () async {
    final backup = await _service.capture();
    if (!mounted) return;
    final saved = await _service.export(backup);
    if (!mounted) return;
    setState(() {
      _message = saved
          ? '备份文件已保存：${_counts(backup)}。\n'
                '将这个文件传到新手机，在本页选择导入即可。'
                '${backup.excludedLocalRecords > 0 ? '\n已排除 ${backup.excludedLocalRecords} 条本地书籍相关记录。' : ''}'
          : '已取消导出';
    });
  });

  Future<void> _pick() => _run('请选择备份文件，读取后会显示预览…', () async {
    setState(() => _preview = null);
    final backup = await _service.pick();
    if (!mounted) return;
    setState(() {
      _preview = backup;
      if (backup == null) _message = '已取消选择';
    });
  });

  Future<void> _restore() async {
    final backup = _preview;
    if (backup == null) return;
    await _run('正在恢复，请稍候…', () async {
      final result = await _service.restore(backup);
      if (!mounted) return;
      setState(() {
        _preview = null;
        _message =
            '恢复完成：新增 ${result.shelf} 条收藏、${result.history} 条进度、'
            '${result.episodes} 集已看标记。\n'
            '保留本机已有收藏/进度 '
            '${backup.shelf.length + backup.history.length - result.shelf - result.history} 条。';
      });
    }, restoring: true);
  }

  static String _counts(LibraryBackup backup) =>
      '${backup.shelf.length} 条收藏、${backup.history.length} 条进度、'
      '${backup.episodeCount} 集已看标记';

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    final preview = _preview;
    final enabled = _busy == null;
    final exportedAt = preview?.createdAt.toLocal().toString().split('.').first;
    return PopScope(
      canPop: enabled,
      child: Scaffold(
        backgroundColor: palette.canvas,
        appBar: AppBar(
          title: const Text('备份与恢复'),
          centerTitle: true,
          backgroundColor: palette.canvas,
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _section(palette, [
                    Text(
                      '换手机，带上收藏和进度',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('包含在线小说、听书、漫画、短剧和漫剧的收藏、已保存的阅读/播放进度，以及已看剧集。'),
                    const SizedBox(height: 8),
                    Text(
                      '不含本地 TXT/EPUB 书籍及其进度、下载缓存、阅读时长、划线和应用设置。'
                      '本地书籍请另行保留原文件。',
                      style: TextStyle(color: palette.muted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '导出前请先退出阅读或暂停播放，让当前进度保存。文件保存在你选择的位置。',
                      style: TextStyle(color: palette.muted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '请保留备份文件：应用日常保存仍会在历史超过 100 条时清理较早记录，仅保留最近约 50 条。',
                      style: TextStyle(color: palette.muted),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: enabled ? _export : null,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('导出备份文件'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: enabled ? _pick : null,
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(preview == null ? '选择备份文件导入' : '选择其他备份文件'),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 16),
                    _section(palette, [
                      Text(
                        '导入预览',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('备份时间：$exportedAt'),
                      const SizedBox(height: 8),
                      Text(_counts(preview)),
                      if (preview.excludedLocalRecords > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          '原备份已排除 ${preview.excludedLocalRecords} 条本地书籍相关记录。',
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Text('同一作品已有收藏或进度时保留本机记录，只补缺失项；已看剧集会合并。可重复导入。'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: enabled ? _restore : null,
                        child: const Text('确认合并到本机'),
                      ),
                    ]),
                  ],
                  if (_busy case final label?) ...[
                    const SizedBox(height: 16),
                    Semantics(liveRegion: true, child: Text(label)),
                  ],
                  if (_message case final message?) ...[
                    const SizedBox(height: 16),
                    _section(palette, [
                      Semantics(liveRegion: true, child: Text(message)),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(HomePalette palette, List<Widget> children) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: palette.line),
    ),
    child: DefaultTextStyle.merge(
      style: TextStyle(color: palette.ink, height: 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}
