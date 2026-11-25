import 'package:encoresheets/scan_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('rectifies and rotates a crop, and rejects crossed corners', () async {
    final image = img.Image(width: 120, height: 80);
    img.fill(image, color: img.ColorRgb8(100, 50, 10));
    final bytes = prepareScanImage(img.encodePng(image));
    const edits = ScanEdits(
      corners: [
        (x: .10, y: .10),
        (x: .80, y: .10),
        (x: .90, y: .90),
        (x: .10, y: .90),
      ],
      rotation: 1,
      saturation: 0,
    );
    final page = correctScanPage(bytes, edits);
    expect(page.height, greaterThan(page.width));
    final color = img.decodeJpg(page.bytes)!.getPixel(5, 5);
    expect((color.r - color.b).abs(), lessThan(4));
    final pdf = await buildScannedPdf([
      (bytes: bytes, edits: edits),
      (bytes: bytes, edits: const ScanEdits()),
    ]);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(
      () => correctScanPage(
        bytes,
        edits.copyWith(corners: edits.corners.reversed.toList()),
      ),
      throwsFormatException,
    );
  });
}
