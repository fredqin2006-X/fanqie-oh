import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fqapp/models/related_series.dart';
import 'package:fqapp/models/series_detail.dart';
import 'package:fqapp/widgets/player/related_series_sheet.dart';

void main() {
  test(
    'official plan cell preserves series IDs and excludes unrelated videos',
    () {
      final fixture =
          jsonDecode(
                File('rust/testdata/series_related.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final entries = RelatedSeries.fromPayload(
        fixture['response'] as Map<String, dynamic>,
        currentSeriesId: fixture['series_id'] as String,
      );
      expect(entries.map((entry) => entry.id), [
        '7612345678901234568',
        '7612345678901234569',
        '7612345678901234570',
      ]);
      expect(entries.first.episodeCount, 36);
      expect(entries[1].unavailable, isTrue);
      expect(entries[2].kind, 'manju');
    },
  );

  test(
    'same-series availability is driven by the album relation, not recommendations',
    () {
      SeriesDetail detail(dynamic relation) => SeriesDetail.fromPayload({
        'code': 0,
        'data': {
          'video_data': {'related_album_id': relation},
        },
      });
      expect(detail('7612345678901234567').hasRelatedSeries, isTrue);
      for (final relation in [null, '', 'bad', 0, -1]) {
        expect(detail(relation).hasRelatedSeries, isFalse);
      }
    },
  );

  testWidgets(
    'unavailable seasons cannot be selected and retry keeps exact target',
    (tester) async {
      var attempts = 0;
      RelatedSeries? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showModalBottomSheet<RelatedSeries>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => RelatedSeriesSheet(
                    seriesId: '1',
                    loader: (_) async {
                      if (++attempts == 1) {
                        throw const FormatException('bad response');
                      }
                      return const [
                        RelatedSeries(id: '2', title: '下一季'),
                        RelatedSeries(id: '3', title: '待上线', unavailable: true),
                      ];
                    },
                  ),
                );
              },
              child: const Text('选系列'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('选系列'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('待上线'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.tap(find.text('下一季'));
      await tester.pumpAndSettle();
      expect(selected?.id, '2');
    },
  );

  testWidgets('closing while loading ignores a late response', (tester) async {
    final pending = Completer<List<RelatedSeries>>();
    await tester.pumpWidget(
      MaterialApp(
        home: RelatedSeriesSheet(seriesId: '1', loader: (_) => pending.future),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(const [RelatedSeries(id: '2', title: '下一季')]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
