import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

typedef MeasureClip = ({Uint8List png, double width, double height});

Future<MeasureClip> copyMeasure(
  PdfPage page,
  Rect area, {
  List<Offset> outline = const [],
  bool cover = false,
}) async {
  final scale = math.min(
    3.0,
    1700 / math.max(page.width * area.width, page.height * area.height),
  );
  final fullWidth = page.width * scale;
  final fullHeight = page.height * scale;
  final pixels = await page.render(
    x: (area.left * fullWidth).floor(),
    y: (area.top * fullHeight).floor(),
    width: math.max(1, (area.width * fullWidth).floor()),
    height: math.max(1, (area.height * fullHeight).floor()),
    fullWidth: fullWidth,
    fullHeight: fullHeight,
    annotationRenderingMode: PdfAnnotationRenderingMode.none,
  );
  if (pixels == null) throw StateError('Could not read the selected measure.');
  try {
    final image = await pixels.createImage();
    try {
      final result = outline.isEmpty && !cover
          ? image
          : await _shapeMeasure(image, area, outline, cover: cover);
      final ByteData? data;
      try {
        data = await result.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        if (result != image) result.dispose();
      }
      if (data == null || data.lengthInBytes > 3 * 1024 * 1024) {
        throw StateError('Choose a smaller section of the score.');
      }
      return (
        png: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: area.width * page.width,
        height: area.height * page.height,
      );
    } finally {
      image.dispose();
    }
  } finally {
    pixels.dispose();
  }
}

Future<ui.Image> _shapeMeasure(
  ui.Image image,
  Rect area,
  List<Offset> outline, {
  required bool cover,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final bounds = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  if (outline.isNotEmpty) {
    canvas.clipPath(
      Path()..addPolygon([
        for (final point in outline)
          Offset(
            (point.dx - area.left) / area.width * bounds.width,
            (point.dy - area.top) / area.height * bounds.height,
          ),
      ], true),
      doAntiAlias: false,
    );
  }
  if (cover) {
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    final samples = <int>[
      for (final y in [0, image.height - 1])
        for (final x in [0, image.width - 1]) (y * image.width + x) * 4,
    ];
    final brightest = samples.reduce(
      (a, b) =>
          rgba[a] + rgba[a + 1] + rgba[a + 2] >=
              rgba[b] + rgba[b + 1] + rgba[b + 2]
          ? a
          : b,
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..color = Color.fromARGB(
          255,
          rgba[brightest],
          rgba[brightest + 1],
          rgba[brightest + 2],
        ),
    );
  } else {
    canvas.drawImage(image, Offset.zero, Paint());
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(image.width, image.height);
  } finally {
    picture.dispose();
  }
}

Rect measurePlacement(PdfPage page, MeasureClip clip, Offset point) {
  final scale = math.min(
    1.0,
    math.min(page.width / clip.width, page.height / clip.height),
  );
  final width = scale * clip.width / page.width;
  final height = scale * clip.height / page.height;
  return Rect.fromLTWH(
    point.dx.clamp(0, 1 - width),
    point.dy.clamp(0, 1 - height),
    width,
    height,
  );
}

class PdfSelectionOutline extends CustomPainter {
  const PdfSelectionOutline(this.points, {required this.freeform});

  final List<Offset> points;
  final bool freeform;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    Offset position(Offset point) =>
        Offset(point.dx * size.width, point.dy * size.height);
    final path = Path();
    if (freeform) {
      path.addPolygon(points.map(position).toList(), true);
    } else {
      path.addRect(
        Rect.fromPoints(position(points.first), position(points.last)),
      );
    }
    canvas.drawPath(path, Paint()..color = const Color(0x331683cd));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff1683cd)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(PdfSelectionOutline oldDelegate) =>
      points != oldDelegate.points || freeform != oldDelegate.freeform;
}
