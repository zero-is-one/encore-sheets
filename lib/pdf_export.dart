import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pdf;
import 'package:pdfrx/pdfrx.dart';

import 'page_ink.dart';
import 'pdf_assembly.dart';

Future<Uint8List> exportScorePdf({
  required XFile source,
  required String name,
  required int first,
  required int last,
  required int pageCount,
  Map<String, dynamic>? annotations,
}) async {
  if (first < 1 || last < first || last > pageCount) {
    throw RangeError('The page range is outside the score.');
  }
  if (annotations == null) {
    if (first == 1 && last == pageCount) return source.readAsBytes();
    final result = await assemblePdf(name, [
      (file: source, first: first, last: last),
    ]);
    return result.readAsBytes();
  }

  await pdfrxFlutterInitialize();
  final document = kIsWeb
      ? await PdfDocument.openData(
          await source.readAsBytes(),
          sourceName: source.name,
        )
      : await PdfDocument.openFile(source.path);
  try {
    final output = pdf.Document();
    final layers = annotations['layers'];
    final visibleLayers = layers is List
        ? [
            for (final layer in layers)
              if (layer case {'visible': true, 'id': final String id}) id,
          ]
        : const ['base'];
    for (var pageNumber = first; pageNumber <= last; pageNumber++) {
      final page = document.pages[pageNumber - 1];
      final ink = PageInk(
        saved: annotations['$pageNumber'] as List? ?? const [],
        visibleLayers: visibleLayers,
      );
      final Uint8List bytes;
      try {
        bytes = await _renderAnnotatedPage(page, ink);
      } finally {
        ink.dispose();
      }
      output.addPage(
        pdf.Page(
          pageFormat: PdfPageFormat(page.width, page.height),
          build: (_) => pdf.Image(pdf.MemoryImage(bytes), fit: pdf.BoxFit.fill),
        ),
      );
    }
    return await output.save();
  } finally {
    await document.dispose();
  }
}

Future<Uint8List> _renderAnnotatedPage(PdfPage page, PageInk ink) async {
  await ink.prepareImages();
  final scale = math.min(2.5, 3200 / math.max(page.width, page.height));
  final width = math.max(1, (page.width * scale).round());
  final height = math.max(1, (page.height * scale).round());
  final pixels = await page.render(width: width, height: height);
  if (pixels == null) throw StateError('Could not render a score page.');
  try {
    final image = await pixels.createImage();
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImage(image, ui.Offset.zero, ui.Paint());
      ink.paint(canvas, ui.Size(width.toDouble(), height.toDouble()));
      final picture = recorder.endRecording();
      try {
        final flattened = await picture.toImage(width, height);
        try {
          final data = await flattened.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data == null) throw StateError('Could not encode a score page.');
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        } finally {
          flattened.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      image.dispose();
    }
  } finally {
    pixels.dispose();
  }
}
