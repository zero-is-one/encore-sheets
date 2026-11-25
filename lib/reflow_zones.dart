import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

typedef ReflowZone = ({int page, double top, double bottom});

List<ReflowZone> detectReflowBands(
  Uint8List pixels,
  int width,
  int height,
  int page,
) {
  final bands = <ReflowZone>[];
  final gap = math.max(6, (height * .026).round());
  final margin = math.max(2, (height * .009).round());
  var first = -1, last = -1;
  void append() {
    if (first < 0) return;
    bands.add((
      page: page,
      top: math.max(0, first - margin) / height,
      bottom: math.min(height, last + 1 + margin) / height,
    ));
  }

  for (var y = 0; y < height; y++) {
    var dark = 0;
    for (var x = width ~/ 20; x < width * .95; x++) {
      final offset = (y * width + x) * 4;
      if (pixels[offset + 3] > 120 &&
          pixels[offset] + pixels[offset + 1] + pixels[offset + 2] < 510)
        dark++;
    }
    if (dark < math.max(3, width ~/ 50)) continue;
    if (first < 0 || y - last > gap) {
      append();
      first = y;
    }
    last = y;
  }
  append();
  return bands.isEmpty ? [(page: page, top: 0, bottom: 1)] : bands;
}

Future<List<ReflowZone>> scanReflowPage(PdfPage page) async {
  const width = 260;
  final height = math.max(1, (width * page.height / page.width).round());
  final image = await page.render(width: width, height: height);
  if (image == null) return [(page: page.pageNumber, top: 0, bottom: 1)];
  try {
    final raster = await image.createImage();
    try {
      final bytes = await raster.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (bytes != null) {
        return detectReflowBands(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          raster.width,
          raster.height,
          page.pageNumber,
        );
      }
      return [(page: page.pageNumber, top: 0, bottom: 1)];
    } finally {
      raster.dispose();
    }
  } finally {
    image.dispose();
  }
}

Future<ui.Image?> renderReflowZone(
  PdfPage page,
  ReflowZone zone,
  double requestedWidth, {
  PdfAnnotationRenderingMode annotations =
      PdfAnnotationRenderingMode.annotationAndForms,
}) async {
  final width = requestedWidth.round().clamp(200, 3000);
  final height = width * page.height / page.width;
  final top = (zone.top * height).floor();
  final bottom = (zone.bottom * height).ceil();
  final image = await page.render(
    width: width,
    height: math.max(1, bottom - top),
    y: top,
    fullWidth: width.toDouble(),
    fullHeight: height,
    annotationRenderingMode: annotations,
  );
  if (image == null) return null;
  try {
    return await image.createImage();
  } finally {
    image.dispose();
  }
}
