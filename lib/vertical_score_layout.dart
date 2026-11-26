import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

int verticalPageAt(
  Rect visible,
  List<Rect> pages, {
  required int first,
  required int last,
}) {
  // Prefer the last page at the bottom even when it is shorter than the view.
  if (visible.top > pages[first - 1].top &&
      visible.bottom >= pages[last - 1].bottom - 1) {
    return last;
  }
  final readingLine = visible.top + visible.height * .25;
  var low = first;
  var high = last;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (pages[middle - 1].bottom < readingLine) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// Lays out an item bookmark as a continuous excerpt while retaining the PDF's
/// original page numbers for navigation, rendering, and annotations.
class VerticalExcerptLayout extends PdfPageLayoutStrategy {
  const VerticalExcerptLayout(this.layout, this.firstPage, this.lastPage);

  final SequentialPagesLayout layout;
  final int firstPage;
  final int lastPage;

  @override
  PdfPageLayout resolve(PdfPageLayoutContext context) {
    if (context.pages.isEmpty) return layout.resolve(context);
    final first = (firstPage - 1).clamp(0, context.pages.length - 1);
    final end = lastPage.clamp(first + 1, context.pages.length);
    final excerpt = layout.resolve(
      PdfPageLayoutContext(
        pages: context.pages.sublist(first, end),
        viewport: context.viewport,
        boundaryMargin: context.boundaryMargin,
      ),
    );
    return PdfPageLayout(
      pageLayouts: [
        for (var i = 0; i < first; i++) const Rect.fromLTWH(0, -1, 0, 0),
        ...excerpt.pageLayouts,
        for (var i = end; i < context.pages.length; i++)
          Rect.fromLTWH(0, excerpt.documentSize.height + 1, 0, 0),
      ],
      documentSize: excerpt.documentSize,
      margin: excerpt.margin,
      fitMode: excerpt.fitMode,
      primaryAxis: Axis.vertical,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VerticalExcerptLayout &&
      other.layout == layout &&
      other.firstPage == firstPage &&
      other.lastPage == lastPage;

  @override
  int get hashCode => Object.hash(layout, firstPage, lastPage);
}
