import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';

Future<Map<String, String>> readEmbeddedPdfInfo(XFile file) async =>
    compute(extractEmbeddedPdfInfo, await file.readAsBytes());

Map<String, String> extractEmbeddedPdfInfo(Uint8List bytes) {
  final info = PdfDocument.open(bytes).info;
  return {
    for (final key in ['Title', 'Author', 'Subject', 'Keywords'])
      if (info[key]?.trim() case final value? when value.isNotEmpty) key: value,
  };
}
