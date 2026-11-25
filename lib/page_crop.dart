import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

class PageCrop {
  const PageCrop({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.angle = 0,
  });

  static const maxMargin = .45;
  static const maxAngle = 12.0;

  final double left;
  final double top;
  final double right;
  final double bottom;
  final double angle;

  static PageCrop? fromJson(Object? json) {
    if (json case [num left, num top, num right, num bottom, num angle]) {
      final margins = [left, top, right, bottom];
      if (margins.any((n) => !n.isFinite || n < 0 || n > maxMargin) ||
          !angle.isFinite ||
          angle.abs() > maxAngle) {
        return null;
      }
      return PageCrop(
        left: left.toDouble(),
        top: top.toDouble(),
        right: right.toDouble(),
        bottom: bottom.toDouble(),
        angle: angle.toDouble(),
      );
    }
    return null;
  }

  List<double> toJson() => [left, top, right, bottom, angle];

  bool get isIdentity =>
      left == 0 && top == 0 && right == 0 && bottom == 0 && angle == 0;

  ui.Rect within(ui.Rect rect) => ui.Rect.fromLTRB(
    rect.left + rect.width * left,
    rect.top + rect.height * top,
    rect.right - rect.width * right,
    rect.bottom - rect.height * bottom,
  );

  PdfRect pdfBounds(PdfPage page) => PdfRect(
    left * page.width,
    (1 - top) * page.height,
    (1 - right) * page.width,
    bottom * page.height,
  );

  PageCrop copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? angle,
  }) => PageCrop(
    left: left ?? this.left,
    top: top ?? this.top,
    right: right ?? this.right,
    bottom: bottom ?? this.bottom,
    angle: angle ?? this.angle,
  );

  PageCrop rotated(int clockwise) => switch (clockwise) {
    1 => PageCrop(
      left: bottom,
      top: left,
      right: top,
      bottom: right,
      angle: angle,
    ),
    2 => PageCrop(
      left: right,
      top: bottom,
      right: left,
      bottom: top,
      angle: angle,
    ),
    3 => PageCrop(
      left: top,
      top: right,
      right: bottom,
      bottom: left,
      angle: angle,
    ),
    _ => this,
  };
}

Future<PageCrop> detectPageMargins(PdfPage page) async {
  final scale = 440 / math.max(page.width, page.height);
  final width = math.max(1, (page.width * scale).round());
  final height = math.max(1, (page.height * scale).round());
  final pixels = await page.render(width: width, height: height);
  if (pixels == null) return const PageCrop();
  try {
    final image = await pixels.createImage();
    try {
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      return data == null
          ? const PageCrop()
          : estimateCrop(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              width,
              height,
            );
    } finally {
      image.dispose();
    }
  } finally {
    pixels.dispose();
  }
}

PageCrop estimateCrop(Uint8List rgba, int width, int height) {
  final rows = List<int>.filled(height, 0);
  final columns = List<int>.filled(width, 0);
  const edge = 3;
  for (var y = edge; y < height - edge; y++) {
    for (var x = edge; x < width - edge; x++) {
      final i = (y * width + x) * 4;
      if (rgba[i + 3] > 128 && rgba[i] + rgba[i + 1] + rgba[i + 2] < 540) {
        rows[y]++;
        columns[x]++;
      }
    }
  }
  final rowThreshold = math.max(2, (width * .006).ceil());
  final columnThreshold = math.max(2, (height * .006).ceil());
  final firstRow = rows.indexWhere((hits) => hits >= rowThreshold);
  final lastRow = rows.lastIndexWhere((hits) => hits >= rowThreshold);
  final firstColumn = columns.indexWhere((hits) => hits >= columnThreshold);
  final lastColumn = columns.lastIndexWhere((hits) => hits >= columnThreshold);
  if (firstRow == -1 || firstColumn == -1) return const PageCrop();
  double margin(double distance, int extent) =>
      (distance / extent - .018).clamp(0.0, PageCrop.maxMargin);
  return PageCrop(
    left: margin(firstColumn.toDouble(), width),
    top: margin(firstRow.toDouble(), height),
    right: margin((width - lastColumn - 1).toDouble(), width),
    bottom: margin((height - lastRow - 1).toDouble(), height),
  );
}
