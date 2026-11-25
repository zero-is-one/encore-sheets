import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pdf;
import 'package:xml/xml.dart';

import 'word_binary_text.dart';

String _decodeText(Uint8List bytes) {
  if (bytes.length >= 2) {
    final little = bytes[0] == 0xff && bytes[1] == 0xfe;
    final big = bytes[0] == 0xfe && bytes[1] == 0xff;
    if (little || big) {
      final view = ByteData.sublistView(bytes);
      return String.fromCharCodes([
        for (var i = 2; i + 1 < bytes.length; i += 2)
          view.getUint16(i, little ? Endian.little : Endian.big),
      ]);
    }
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return String.fromCharCodes(bytes.map(windowsTextCode));
  }
}

String _extractDocx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final part = archive.findFile('word/document.xml');
  if (part == null || !part.isFile || part.size > 8 * 1024 * 1024) {
    throw const FormatException(
      'The Word document body is missing or too large.',
    );
  }
  final document = XmlDocument.parse(utf8.decode(part.content));
  final body = document.descendants.whereType<XmlElement>().firstWhere(
    (element) => element.name.local == 'body',
  );
  final lines = <String>[];
  for (final paragraph in body.descendants.whereType<XmlElement>()) {
    if (paragraph.name.local != 'p') continue;
    final row = StringBuffer();
    for (final element in paragraph.descendants.whereType<XmlElement>()) {
      row.write(switch (element.name.local) {
        't' => element.innerText,
        'tab' => '\t',
        'br' || 'cr' => '\n',
        _ => '',
      });
    }
    lines.add(row.toString());
  }
  return lines.join('\n');
}

String _extractRtf(String source) {
  if (!source.trimLeft().startsWith(r'{\rtf')) {
    throw const FormatException('Invalid rich text document.');
  }
  final tokens = RegExp(
    r"""[{}]|\\(?:'[0-9a-fA-F]{2}|[a-zA-Z]+-?\d* ?|[^\r\n])|[^{}\\]+""",
  );
  final control = RegExp(r'^([A-Za-z]+)(-?\d+)? ?$');
  final groups = <({bool skip, int fallback})>[];
  final result = StringBuffer();
  var state = (skip: false, fallback: 1);
  var discard = 0;
  void text(String value) {
    if (state.skip || value.isEmpty) return;
    if (discard > 0) {
      final skipped = discard.clamp(0, value.length);
      discard -= skipped;
      value = value.substring(skipped);
    }
    result.write(value);
  }

  for (final match in tokens.allMatches(source)) {
    final token = match[0]!;
    if (token == '{') {
      groups.add(state);
    } else if (token == '}') {
      if (groups.isEmpty)
        throw const FormatException('Unbalanced rich text document.');
      state = groups.removeLast();
    } else if (!token.startsWith('\\')) {
      text(token.replaceAll(RegExp(r'[\r\n]'), ''));
    } else {
      final word = token.substring(1);
      if (word.startsWith("'")) {
        text(
          String.fromCharCode(
            windowsTextCode(int.parse(word.substring(1), radix: 16)),
          ),
        );
        continue;
      }
      if (word == '*') state = (skip: true, fallback: state.fallback);
      final parsed = control.firstMatch(word);
      final command = parsed?[1] ?? word;
      final argument = int.tryParse(parsed?[2] ?? '');
      switch (command) {
        case 'fonttbl' ||
            'colortbl' ||
            'stylesheet' ||
            'info' ||
            'pict' ||
            'object' ||
            'header' ||
            'footer' ||
            'fldinst':
          state = (skip: true, fallback: state.fallback);
        case 'uc':
          state = (skip: state.skip, fallback: (argument ?? 1).clamp(0, 10));
        case 'u':
          if (!state.skip && argument != null) {
            result.writeCharCode(argument & 0xffff);
            discard = state.fallback;
          }
        case 'par' || 'line':
          text('\n');
        case 'tab':
          text('\t');
        case '\\' || '{' || '}':
          text(command);
        case '~':
          text(' ');
        case 'emdash':
          text('—');
        case 'endash':
          text('–');
      }
    }
  }
  if (groups.isNotEmpty)
    throw const FormatException('Unbalanced rich text document.');
  return result.toString();
}

Future<Uint8List> convertTextScore(
  Uint8List bytes, {
  required String extension,
  required String title,
}) {
  if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
    throw const FormatException('Choose a non-empty document under 8 MB.');
  }
  final decoded = switch (extension) {
    'txt' => _decodeText(bytes),
    'rtf' => _extractRtf(_decodeText(bytes)),
    'docx' => _extractDocx(bytes),
    'doc'
        when bytes.length > 6 &&
            latin1.decode(bytes.take(6).toList()).startsWith(r'{\rtf') =>
      _extractRtf(_decodeText(bytes)),
    'doc' => extractWordBinaryText(bytes),
    _ => throw const FormatException(
      'Choose a TXT, RTF, DOC, or DOCX document.',
    ),
  };
  final text = decoded
      .replaceAll(RegExp(r'[\u0000-\u0008\u000b-\u000c\u000e-\u001f]'), '')
      .trim();
  if (text.isEmpty || text.length > 250000) {
    throw const FormatException(
      'The document contains no convertible text or is too long.',
    );
  }
  final document = pdf.Document(title: title);
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  document.addPage(
    pdf.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pdf.EdgeInsets.all(42),
      maxPages: 160,
      build: (_) => [
        for (final line in lines)
          pdf.Padding(
            padding: const pdf.EdgeInsets.only(bottom: 3),
            child: pdf.Text(
              line.isEmpty ? ' ' : line.replaceAll('\t', '    '),
              style: const pdf.TextStyle(fontSize: 11, lineSpacing: 2),
            ),
          ),
      ],
    ),
  );
  return document.save();
}
