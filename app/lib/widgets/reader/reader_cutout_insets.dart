import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

// Note: Android 9/10 omit cutout viewPadding while system bars are hidden.
// See .agents/notes/implemented/bug-fix/2026-10-12-reader-system-bars.md.
MediaQueryData readerMediaQueryWithCutoutInsets(MediaQueryData data) {
  var cutout = EdgeInsets.zero;
  final screen = Offset.zero & data.size;
  for (final feature in data.displayFeatures) {
    if (feature.type != ui.DisplayFeatureType.cutout ||
        !feature.bounds.overlaps(screen)) {
      continue;
    }
    final bounds = feature.bounds.intersect(screen);
    // The platform's safe area takes precedence even if it protects a corner
    // cutout from a different edge than the fallback below would choose.
    if (bounds.bottom <= data.viewPadding.top ||
        bounds.right <= data.viewPadding.left ||
        bounds.top >= data.size.height - data.viewPadding.bottom ||
        bounds.left >= data.size.width - data.viewPadding.right) {
      continue;
    }
    // Punch holes need not touch an edge. Reserve the smallest edge strip
    // containing the cutout, including its gap from the screen edge.
    final top = bounds.bottom;
    final left = bounds.right;
    final right = data.size.width - bounds.left;
    final bottom = data.size.height - bounds.top;
    final depth = math.min(math.min(top, bottom), math.min(left, right));
    final inset = switch (depth) {
      _ when depth == top => EdgeInsets.only(top: top),
      _ when depth == bottom => EdgeInsets.only(bottom: bottom),
      _ when depth == left => EdgeInsets.only(left: left),
      _ => EdgeInsets.only(right: right),
    };
    cutout = _maxInsets(cutout, inset);
  }
  if (cutout == EdgeInsets.zero) return data;
  // Android 11+ already reports cutout viewPadding. Merge, never add twice;
  // keep keyboard occlusion separate from the SafeArea consumed by content.
  return data.copyWith(
    viewPadding: _maxInsets(data.viewPadding, cutout),
    padding: _maxInsets(
      data.padding,
      EdgeInsets.fromLTRB(
        math.max(0, cutout.left - data.viewInsets.left),
        math.max(0, cutout.top - data.viewInsets.top),
        math.max(0, cutout.right - data.viewInsets.right),
        math.max(0, cutout.bottom - data.viewInsets.bottom),
      ),
    ),
  );
}

EdgeInsets _maxInsets(EdgeInsets a, EdgeInsets b) => EdgeInsets.fromLTRB(
  math.max(a.left, b.left),
  math.max(a.top, b.top),
  math.max(a.right, b.right),
  math.max(a.bottom, b.bottom),
);
