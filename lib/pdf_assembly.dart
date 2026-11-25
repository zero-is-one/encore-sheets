import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

Future<XFile> assemblePdf(
  String name,
  List<({XFile file, int? first, int? last})> parts,
) async {
  await pdfrxFlutterInitialize();
  final sources = <PdfDocument>[];
  PdfDocument? output;
  try {
    final pages = <PdfPage>[];
    for (final part in parts) {
      final source = kIsWeb
          ? await PdfDocument.openData(
              await part.file.readAsBytes(),
              sourceName: part.file.name,
            )
          : await PdfDocument.openFile(part.file.path);
      sources.add(source);
      final first = part.first ?? 1;
      final last = part.last ?? source.pages.length;
      if (first < 1 || first > last || last > source.pages.length) {
        throw RangeError('Page range is outside the source PDF.');
      }
      pages.addAll(source.pages.getRange(first - 1, last));
    }
    if (pages.isEmpty) throw ArgumentError('Select at least one page.');
    output = await PdfDocument.createNew(sourceName: name);
    output.pages = pages;
    return XFile.fromData(
      await output.encodePdf(),
      name: name,
      mimeType: 'application/pdf',
    );
  } finally {
    await output?.dispose();
    for (final source in sources.reversed) {
      await source.dispose();
    }
  }
}
