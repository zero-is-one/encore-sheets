import 'dart:ui' show Offset;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import 'score_library.dart';

class EditedPdfPage {
  const EditedPdfPage(this.page, {this.originalPage, this.rotation = 0});

  final PdfPage page;
  final int? originalPage;
  final int rotation;

  PdfPage get transformed => page.rotatedBy(PdfPageRotation.values[rotation]);

  EditedPdfPage rotate() => EditedPdfPage(
    page,
    originalPage: originalPage,
    rotation: (rotation + 1) % 4,
  );

  Offset transform(double x, double y) => switch (rotation) {
    1 => Offset(1 - y, x),
    2 => Offset(1 - x, 1 - y),
    3 => Offset(y, 1 - x),
    _ => Offset(x, y),
  };
}

Future<PdfDocument> openRearrangeDocument(XFile source) async {
  await pdfrxFlutterInitialize();
  return kIsWeb
      ? PdfDocument.openData(
          await source.readAsBytes(),
          sourceName: source.name,
        )
      : PdfDocument.openFile(source.path);
}

Future<XFile> writeRearrangedPdf(String name, List<EditedPdfPage> pages) async {
  if (pages.isEmpty) throw ArgumentError('Keep at least one page.');
  final output = await PdfDocument.createNew(sourceName: name);
  try {
    output.pages = [for (final page in pages) page.transformed];
    return XFile.fromData(
      await output.encodePdf(),
      name: name,
      mimeType: 'application/pdf',
    );
  } finally {
    await output.dispose();
  }
}

({ScoreEntry score, Map<String, dynamic> annotations}) remapScorePages(
  ScoreEntry source,
  Map<String, dynamic> annotations,
  List<EditedPdfPage> pages,
) {
  final destination = <int, List<int>>{};
  for (final (index, page) in pages.indexed) {
    if (page.originalPage case final origin?) {
      (destination[origin] ??= []).add(index + 1);
    }
  }
  final mappedInk = <String, dynamic>{
    if (annotations.containsKey('layers')) 'layers': annotations['layers'],
  };
  final splits = <int, double>{};
  for (final (index, page) in pages.indexed) {
    final origin = page.originalPage;
    final strokes = annotations['$origin'];
    if (strokes is List) {
      mappedInk['${index + 1}'] = [
        for (final stroke in strokes.cast<Map<String, dynamic>>())
          {
            ...stroke,
            'points': [
              for (final [num x, num y] in stroke['points'] as List)
                [
                  page.transform(x.toDouble(), y.toDouble()).dx,
                  page.transform(x.toDouble(), y.toDouble()).dy,
                ],
            ],
          },
      ];
    }
    if (source.halfSplits[origin] case final split? when page.rotation.isEven) {
      splits[index + 1] = page.rotation == 2 ? 1 - split : split;
    }
  }

  final bookmarks = <ScoreBookmark>[];
  for (final bookmark in source.bookmarks) {
    final end = bookmark.endPage;
    if (end == null) {
      if (destination[bookmark.page]?.firstOrNull case final page?) {
        bookmarks.add(ScoreBookmark(bookmark.id, bookmark.title, page));
      }
      continue;
    }
    final range = <int>[
      for (final old in destination.keys)
        if (old >= bookmark.page && old <= end) ...destination[old]!,
    ]..sort();
    if (range.isNotEmpty) {
      bookmarks.add(
        ScoreBookmark(
          bookmark.id,
          bookmark.title,
          range.first,
          endPage: range.last,
        ),
      );
    }
  }

  JumpPoint remap(JumpPoint point, int page) {
    final position = pages[page - 1].transform(point.x, point.y);
    return JumpPoint(page, position.dx, position.dy);
  }

  final jumps = <ScoreJump>[
    for (final jump in source.jumps)
      if (destination[jump.target.page]?.firstOrNull case final target?)
        for (final page in destination[jump.source.page] ?? <int>[])
          ScoreJump(
            jump.title,
            remap(jump.source, page),
            remap(jump.target, target),
          ),
  ];
  return (
    score: source.copyWith(
      page: destination[source.page]?.firstOrNull ?? 1,
      bookmarks: bookmarks,
      flags: [
        for (final (index, page) in pages.indexed)
          if (source.flags.contains(page.originalPage)) index + 1,
      ],
      jumps: jumps,
      halfSplits: splits,
      pageNotes: {
        for (final (index, page) in pages.indexed)
          if (source.pageNotes[page.originalPage] case final note?)
            index + 1: note,
      },
      actions: [
        for (final action in source.actions)
          for (final page in destination[action.page] ?? const <int>[])
            if (pages[page - 1].transform(action.x, action.y)
                case final position)
              action.reposition(page, position.dx, position.dy),
      ],
      crops: {
        for (final (index, page) in pages.indexed)
          if (source.crops[page.originalPage] case final crop?)
            index + 1: crop.rotated(page.rotation),
      },
    ),
    annotations: mappedInk,
  );
}
