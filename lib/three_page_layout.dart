import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

/// Displays consecutive three-page groups on a wide reader viewport.
final class ThreePageLayout extends PdfPageLayoutStrategy {
  const ThreePageLayout();

  @override
  PdfPageLayout resolve(PdfPageLayoutContext context) {
    const gap = 8.0;
    final viewport = context.viewport;
    if (viewport.width <= gap * 4 || viewport.height <= gap * 2) {
      return const FacingPagesLayout(fitMode: PdfFitMode.fit).resolve(context);
    }
    final column = (viewport.width - gap * 4) / 3;
    final pages = context.pages;
    final rects = <Rect>[];
    final spreads = <PdfPageRange>[];
    var top = 0.0;
    for (var start = 0; start < pages.length; start += 3) {
      final count = math.min(3, pages.length - start);
      final widths = <double>[];
      final heights = <double>[];
      for (var i = 0; i < count; i++) {
        final page = pages[start + i];
        final scale = math.min(
          column / page.width,
          (viewport.height - gap * 2) / page.height,
        );
        widths.add(page.width * scale);
        heights.add(page.height * scale);
      }
      final height = context.paged
          ? viewport.height
          : heights.reduce(math.max) + gap * 2;
      final startX =
          (viewport.width - (column * count + gap * (count - 1))) / 2;
      for (var i = 0; i < count; i++) {
        rects.add(
          Rect.fromLTWH(
            startX + i * (column + gap) + (column - widths[i]) / 2,
            top + (height - heights[i]) / 2,
            widths[i],
            heights[i],
          ),
        );
      }
      spreads.add(PdfPageRange(start + 1, start + count));
      top += height;
    }
    return PdfPageLayout(
      pageLayouts: rects,
      documentSize: Size(viewport.width, top),
      margin: gap,
      fitMode: PdfFitMode.fit,
      primaryAxis: Axis.vertical,
      spreads: spreads,
    );
  }

  @override
  bool operator ==(Object other) => other is ThreePageLayout;

  @override
  int get hashCode => runtimeType.hashCode;
}
