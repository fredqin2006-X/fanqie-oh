import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/related_series.dart';
import '../../services/api_client.dart';
import '../../services/backend_transport.dart';
import '../../services/user_facing_error.dart';

class RelatedSeriesSheet extends StatefulWidget {
  const RelatedSeriesSheet({super.key, required this.seriesId, this.loader});

  final String seriesId;
  final Future<List<RelatedSeries>> Function(String)? loader;

  static Future<RelatedSeries?> show(BuildContext context, String seriesId) =>
      showModalBottomSheet<RelatedSeries>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => RelatedSeriesSheet(seriesId: seriesId),
      );

  @override
  State<RelatedSeriesSheet> createState() => _RelatedSeriesSheetState();
}

class _RelatedSeriesSheetState extends State<RelatedSeriesSheet> {
  BackendRequest? _request;
  bool _loading = true;
  String? _error;
  List<RelatedSeries> _items = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _request?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _request?.cancel();
    final request = _request = BackendRequest();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ApiClient.instance
          .withCancellation(
            request,
            () =>
                widget.loader?.call(widget.seriesId) ??
                ApiClient.instance.relatedSeries(widget.seriesId),
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted || !identical(request, _request)) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      request.cancel();
      if (!mounted || !identical(request, _request)) return;
      setState(() {
        _error = userFacingError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.65,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '同系列剧',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(child: _body(context)),
      ],
    ),
  );

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('暂无可切换的同系列剧'));
    }
    return ListView.separated(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 80),
      itemBuilder: (context, index) {
        final item = _items[index];
        final placeholder = ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.movie_outlined)),
        );
        return ListTile(
          key: ValueKey('related-series-${item.id}'),
          enabled: !item.unavailable,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 44,
              height: 60,
              child: item.cover.isEmpty
                  ? placeholder
                  : CachedNetworkImage(
                      imageUrl: ApiClient.instance.absoluteUrl(item.cover),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => placeholder,
                    ),
            ),
          ),
          title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            item.unavailable
                ? '暂不可播放'
                : item.episodeCount > 0
                ? '共 ${item.episodeCount} 集'
                : '查看剧集',
          ),
          trailing: item.unavailable ? null : const Icon(Icons.chevron_right),
          onTap: item.unavailable ? null : () => Navigator.pop(context, item),
        );
      },
    );
  }
}
