import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pdf;

typedef ScanPoint = ({double x, double y});

class ScanEdits {
  const ScanEdits({
    this.corners = const [
      (x: 0, y: 0),
      (x: 1, y: 0),
      (x: 1, y: 1),
      (x: 0, y: 1),
    ],
    this.rotation = 0,
    this.brightness = 1,
    this.contrast = 1,
    this.saturation = 1,
  });

  final List<ScanPoint> corners;
  final int rotation;
  final double brightness;
  final double contrast;
  final double saturation;

  ScanEdits copyWith({
    List<ScanPoint>? corners,
    int? rotation,
    double? brightness,
    double? contrast,
    double? saturation,
  }) => ScanEdits(
    corners: corners ?? this.corners,
    rotation: rotation ?? this.rotation,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
  );
}

Uint8List prepareScanImage(Uint8List bytes, {int limit = 2600}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image format');
  final image = img.bakeOrientation(img.Image.from(decoded, noAnimation: true));
  final longest = math.max(image.width, image.height);
  final resized = longest <= limit
      ? image
      : img.copyResize(
          image,
          width: math.max(1, (image.width * limit / longest).round()),
          height: math.max(1, (image.height * limit / longest).round()),
          interpolation: img.Interpolation.average,
        );
  return img.encodePng(resized);
}

({Uint8List bytes, int width, int height}) correctScanPage(
  Uint8List bytes,
  ScanEdits edits,
) {
  final source = img.decodePng(bytes)!;
  final corners = edits.corners;
  if (corners.length != 4 ||
      corners.any(
        (p) =>
            !p.x.isFinite ||
            !p.y.isFinite ||
            p.x < 0 ||
            p.x > 1 ||
            p.y < 0 ||
            p.y > 1,
      )) {
    throw const FormatException('Keep all four corners inside the image.');
  }
  for (var i = 0; i < 4; i++) {
    final a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4];
    if ((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) < .0003) {
      throw const FormatException(
        'Use four distinct corners in clockwise order.',
      );
    }
  }
  final [a, b, c, d] = corners;
  final dx1 = b.x - c.x, dx2 = d.x - c.x, dx3 = a.x - b.x + c.x - d.x;
  final dy1 = b.y - c.y, dy2 = d.y - c.y, dy3 = a.y - b.y + c.y - d.y;
  final determinant = dx1 * dy2 - dx2 * dy1;
  final g = (dx3 * dy2 - dx2 * dy3) / determinant;
  final h = (dx1 * dy3 - dx3 * dy1) / determinant;
  final ax = b.x - a.x + g * b.x, bx = d.x - a.x + h * d.x;
  final ay = b.y - a.y + g * b.y, by = d.y - a.y + h * d.y;
  double length(ScanPoint p, ScanPoint q) {
    final x = (p.x - q.x) * source.width, y = (p.y - q.y) * source.height;
    return math.sqrt(x * x + y * y);
  }

  final width = math.max(2, math.max(length(a, b), length(d, c)).round());
  final height = math.max(2, math.max(length(a, d), length(b, c)).round());
  final output = img.Image(width: width, height: height);
  for (final pixel in output) {
    final u = pixel.x / (width - 1), v = pixel.y / (height - 1);
    final w = 1 + g * u + h * v;
    final x = ((a.x + ax * u + bx * v) / w).clamp(0, 1) * (source.width - 1);
    final y = ((a.y + ay * u + by * v) / w).clamp(0, 1) * (source.height - 1);
    final color = source.getPixelInterpolate(
      x,
      y,
      interpolation: img.Interpolation.linear,
    );
    final alpha = color.aNormalized;
    pixel.setRgb(
      (color.rNormalized * alpha + 1 - alpha) * 255,
      (color.gNormalized * alpha + 1 - alpha) * 255,
      (color.bNormalized * alpha + 1 - alpha) * 255,
    );
  }
  final rotated = edits.rotation % 4 == 0
      ? output
      : img.copyRotate(output, angle: (edits.rotation % 4) * 90);
  img.adjustColor(
    rotated,
    brightness: edits.brightness,
    contrast: edits.contrast,
    saturation: edits.saturation,
  );
  return (
    bytes: img.encodeJpg(rotated, quality: 92),
    width: rotated.width,
    height: rotated.height,
  );
}

Future<Uint8List> buildScannedPdf(
  List<({Uint8List bytes, ScanEdits edits})> pages,
) async {
  final document = pdf.Document();
  for (final page in pages) {
    final image = correctScanPage(page.bytes, page.edits);
    final scale = math.min(612 / image.width, 792 / image.height);
    final picture = pdf.MemoryImage(image.bytes);
    document.addPage(
      pdf.Page(
        pageFormat: PdfPageFormat(image.width * scale, image.height * scale),
        build: (_) => pdf.Image(picture, fit: pdf.BoxFit.fill),
      ),
    );
  }
  return document.save();
}
