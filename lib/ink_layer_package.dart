import 'dart:convert';
import 'dart:typed_data';

import 'page_ink.dart';

const inkLayerExtension = 'encorelayer.json';
const maxInkLayerBytes = 16 * 1024 * 1024;

Uint8List encodeInkLayer(
  InkLayer layer,
  String scoreDigest,
  Map<String, dynamic> snapshot,
) {
  final pages = <String, List<Map<String, dynamic>>>{};
  for (final entry in snapshot.entries) {
    if (int.tryParse(entry.key) == null) continue;
    final strokes = [
      for (final stroke in (entry.value as List).cast<Map<String, dynamic>>())
        if ((stroke['layer'] ?? defaultInkLayer.id) == layer.id)
          (Map<String, dynamic>.of(stroke)..remove('layer')),
    ];
    if (strokes.isNotEmpty) pages[entry.key] = strokes;
  }
  if (pages.isEmpty) throw const FormatException('This layer has no marks.');
  return utf8.encode(
    jsonEncode({
      'version': 1,
      'name': layer.name,
      'score': scoreDigest,
      'pages': pages,
    }),
  );
}

({String name, Map<int, List<Map<String, dynamic>>> pages}) decodeInkLayer(
  Uint8List bytes, {
  required String scoreDigest,
  required int pageCount,
  required String layerId,
}) {
  if (bytes.length > maxInkLayerBytes) {
    throw const FormatException('The annotation layer is too large.');
  }
  final data = jsonDecode(utf8.decode(bytes));
  if (data is! Map<String, dynamic> ||
      data['version'] != 1 ||
      data['name'] is! String ||
      data['pages'] is! Map<String, dynamic>) {
    throw const FormatException('Invalid annotation layer file.');
  }
  if (data['score'] != scoreDigest) {
    throw const FormatException('Open the matching PDF to import this layer.');
  }
  final name = (data['name'] as String).trim();
  if (name.isEmpty || name.length > 80) {
    throw const FormatException('Invalid annotation layer name.');
  }
  final pages = <int, List<Map<String, dynamic>>>{};
  for (final entry in (data['pages'] as Map<String, dynamic>).entries) {
    final page = int.tryParse(entry.key);
    final marks = entry.value;
    if (page == null ||
        page < 1 ||
        page > pageCount ||
        marks is! List ||
        marks.isEmpty ||
        pages.containsKey(page)) {
      throw const FormatException('Invalid annotation layer page.');
    }
    pages[page] = [for (final mark in marks) _readMark(mark, layerId)];
  }
  if (pages.isEmpty) throw const FormatException('This layer has no marks.');
  return (name: name, pages: pages);
}

Map<String, dynamic> _readMark(Object? mark, String layerId) {
  if (mark is! Map<String, dynamic> ||
      !InkTool.values.any((tool) => tool.name == mark['tool']) ||
      mark['points'] is! List ||
      (mark['points'] as List).isEmpty ||
      !(mark['points'] as List).every(
        (point) => point is List && point.length == 2 && point.every(_finite),
      ) ||
      (mark['width'] != null && !_finite(mark['width'])) ||
      (mark['color'] != null && mark['color'] is! int) ||
      (mark['text'] != null && mark['text'] is! String) ||
      (mark['raster'] != null && mark['raster'] is! String) ||
      (mark['sampleWidths'] != null &&
          (mark['sampleWidths'] is! List ||
              !(mark['sampleWidths'] as List).every(_finite)))) {
    throw const FormatException('Invalid mark in annotation layer.');
  }
  return {...mark, 'layer': layerId};
}

bool _finite(Object? value) => value is num && value.isFinite;
