import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fqapp/widgets/reader/reader_cutout_insets.dart';

void main() {
  test('no cutout leaves existing insets untouched', () {
    const data = MediaQueryData(padding: EdgeInsets.only(top: 24));
    expect(readerMediaQueryWithCutoutInsets(data), same(data));
  });

  final cases = [
    (
      const Size(390, 800),
      const Rect.fromLTWH(150, 0, 90, 32),
      const EdgeInsets.only(top: 32),
    ),
    // A punch hole can be inset from both the top and the side of the screen.
    (
      const Size(390, 800),
      const Rect.fromLTWH(8, 8, 32, 24),
      const EdgeInsets.only(top: 32),
    ),
    (
      const Size(800, 390),
      const Rect.fromLTWH(8, 150, 24, 90),
      const EdgeInsets.only(left: 32),
    ),
    (
      const Size(800, 390),
      const Rect.fromLTWH(768, 150, 24, 90),
      const EdgeInsets.only(right: 32),
    ),
    (
      const Size(390, 800),
      const Rect.fromLTWH(150, 768, 90, 24),
      const EdgeInsets.only(bottom: 32),
    ),
  ];
  for (final (size, bounds, expected) in cases) {
    test('cutout $bounds reserves $expected in $size', () {
      final data = MediaQueryData(
        size: size,
        displayFeatures: [_cutout(bounds)],
      );
      final result = readerMediaQueryWithCutoutInsets(data);
      expect(result.padding, expected);
      expect(result.viewPadding, expected);
    });
  }

  test(
    'reported safe area and multiple cutouts merge without double padding',
    () {
      final data = MediaQueryData(
        size: const Size(390, 800),
        padding: const EdgeInsets.only(top: 48, bottom: 24),
        viewPadding: const EdgeInsets.only(top: 48, bottom: 24),
        displayFeatures: [
          _cutout(const Rect.fromLTWH(160, 0, 40, 32)),
          _cutout(const Rect.fromLTWH(220, 0, 40, 40)),
        ],
      );
      final result = readerMediaQueryWithCutoutInsets(data);
      expect(result.padding, data.padding);
      expect(result.viewPadding, data.viewPadding);
      expect(readerMediaQueryWithCutoutInsets(result), result);
      final consumed = result.removePadding(
        removeTop: true,
        removeBottom: true,
      );
      expect(consumed.padding, EdgeInsets.zero);
    },
  );

  test('platform protection takes precedence at a screen corner', () {
    final data = MediaQueryData(
      size: const Size(390, 800),
      padding: const EdgeInsets.only(top: 48),
      viewPadding: const EdgeInsets.only(top: 48),
      displayFeatures: [_cutout(const Rect.fromLTWH(0, 0, 24, 40))],
    );
    // Reserving 24px on the left would be redundant: the OS top inset
    // already keeps all content out of the cutout.
    expect(readerMediaQueryWithCutoutInsets(data), same(data));
  });

  test(
    'keyboard replaces bottom safe padding without erasing physical insets',
    () {
      final data = MediaQueryData(
        size: const Size(390, 800),
        viewInsets: const EdgeInsets.only(bottom: 300),
        displayFeatures: [_cutout(const Rect.fromLTWH(150, 768, 90, 24))],
      );
      final result = readerMediaQueryWithCutoutInsets(data);
      expect(result.padding, EdgeInsets.zero);
      expect(result.viewPadding.bottom, 32);
      expect(result.viewInsets.bottom, 300);
    },
  );

  test('hinges and cutouts outside the window do not become edge padding', () {
    final data = MediaQueryData(
      size: const Size(800, 390),
      displayFeatures: [
        const ui.DisplayFeature(
          bounds: Rect.fromLTWH(395, 0, 10, 390),
          type: ui.DisplayFeatureType.hinge,
          state: ui.DisplayFeatureState.postureFlat,
        ),
        _cutout(const Rect.fromLTWH(900, 0, 20, 30)),
      ],
    );
    expect(readerMediaQueryWithCutoutInsets(data), same(data));
  });
}

ui.DisplayFeature _cutout(Rect bounds) => ui.DisplayFeature(
  bounds: bounds,
  type: ui.DisplayFeatureType.cutout,
  state: ui.DisplayFeatureState.unknown,
);
