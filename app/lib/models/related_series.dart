/// A same-series entry from scene=10, data[0].video_data (official lo3/f.java).
/// Note: .agents/notes/implemented/feature/2026-10-15-related-series.md
class RelatedSeries {
  const RelatedSeries({
    required this.id,
    required this.title,
    this.cover = '',
    this.episodeCount = 0,
    this.kind = 'video',
    this.unavailable = false,
  });

  final String id;
  final String title;
  final String cover;
  final int episodeCount;
  final String kind;
  final bool unavailable;

  static List<RelatedSeries> fromPayload(
    Map<String, dynamic> payload, {
    required String currentSeriesId,
  }) {
    final data = payload['data'];
    if (data is! List || data.isEmpty) return const [];
    final cell = data.first;
    if (cell is! Map || cell['video_data'] is! List) return const [];
    final seen = <String>{currentSeriesId};
    final result = <RelatedSeries>[];
    // Only the first cell is the official same-series result. Later cells may
    // contain general recommendations; do not flatten them into this list.
    for (final entry in cell['video_data'] as List) {
      if (entry is! Map) continue;
      final id = _id(entry['series_id_str']) ?? _id(entry['series_id']);
      final title = _text(entry['title']);
      if (id == null || title.isEmpty || seen.contains(id)) continue;
      final type = _integer(entry['content_type']);
      // Upcoming series stay visible as unavailable; no reservation endpoint.
      if (type != null && !{1, 1002, 1004, 1007}.contains(type)) continue;
      seen.add(id);
      final episodes = _integer(entry['episode_cnt']) ?? 0;
      result.add(
        RelatedSeries(
          id: id,
          title: title,
          cover: _text(entry['cover']),
          episodeCount: episodes > 0 ? episodes : 0,
          kind: type == 1004 || type == 1007 ? 'manju' : 'video',
          unavailable:
              entry['disable_play'] == true ||
              entry['disable_play'] == 1 ||
              type == 1002 ||
              type == 1007,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  static String _text(dynamic value) => value is String ? value.trim() : '';

  static int? _integer(dynamic value) => value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;

  static String? _id(dynamic value) {
    // Doubles cannot faithfully represent these 19-digit IDs.
    if (value is! String && value is! int) return null;
    final id = '$value'.trim();
    return RegExp(r'^[1-9][0-9]*$').hasMatch(id) ? id : null;
  }
}
