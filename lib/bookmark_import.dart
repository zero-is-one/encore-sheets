import 'package:pdfrx/pdfrx.dart';

typedef BookmarkCandidate = ({String title, int page, int? endPage});

List<List<String>> parseBookmarkTable(String contents, String delimiter) {
  final text = contents
      .replaceFirst('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  void flushField() {
    row.add(field.toString().trim());
    field = StringBuffer();
  }

  void flushRow() {
    flushField();
    if (row.any((value) => value.isNotEmpty)) rows.add(row);
    row = [];
  }

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '"' && quoted) {
      if (i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = false;
      }
    } else if (quoted) {
      field.write(char);
    } else if (char == '"' && field.isEmpty) {
      quoted = true;
    } else if (char == delimiter) {
      flushField();
    } else if (char == '\n') {
      flushRow();
    } else {
      field.write(char);
    }
  }
  if (quoted)
    throw const FormatException('The bookmark table has an unclosed quote.');
  flushRow();
  return rows;
}

List<BookmarkCandidate> outlineBookmarks(
  List<PdfOutlineNode> nodes,
  int pageCount,
) => [
  for (final node in nodes) ...[
    if (node.dest?.pageNumber case final page?
        when page >= 1 && page <= pageCount && node.title.trim().isNotEmpty)
      (title: node.title.trim(), page: page, endPage: null),
    ...outlineBookmarks(node.children, pageCount),
  ],
];

class BookmarkPageIndex {
  BookmarkPageIndex(this.document);

  final PdfDocument document;
  final _pageText = <int, Future<String>>{};

  Future<List<int>> find(String title) async {
    String normalize(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final query = normalize(title);
    if (query.isEmpty) return [];
    final matches = <int>[];
    for (final page in document.pages) {
      final text = await _pageText.putIfAbsent(page.pageNumber, () async {
        return normalize((await page.loadText())?.fullText ?? '');
      });
      if (text.contains(query)) matches.add(page.pageNumber);
    }
    return matches;
  }

  Future<({List<BookmarkCandidate> candidates, int skipped})> importTable(
    String contents,
    String delimiter,
  ) async {
    final rows = parseBookmarkTable(contents, delimiter);
    if (rows.isEmpty) return (candidates: <BookmarkCandidate>[], skipped: 0);
    final header = rows.first
        .map((field) => field.toLowerCase().replaceAll(RegExp(r'[ _-]'), ''))
        .toList();
    final titleColumn = header.indexWhere(
      (value) => const {'title', 'name', 'bookmark'}.contains(value),
    );
    final hasHeader = titleColumn >= 0;
    final pageColumn = header.indexWhere(
      (value) => const {'page', 'start', 'startpage', 'from'}.contains(value),
    );
    final endColumn = header.indexWhere(
      (value) => const {'end', 'endpage', 'to'}.contains(value),
    );
    String column(List<String> row, int index) =>
        index >= 0 && index < row.length ? row[index] : '';
    final candidates = <BookmarkCandidate>[];
    var skipped = 0;
    for (final row in hasHeader ? rows.skip(1) : rows) {
      final pageFirst =
          !hasHeader && row.length > 1 && int.tryParse(row.first) != null;
      final title = column(
        row,
        hasHeader
            ? titleColumn
            : pageFirst
            ? 1
            : 0,
      );
      final start = column(
        row,
        hasHeader
            ? pageColumn
            : pageFirst
            ? 0
            : 1,
      );
      final end = column(row, hasHeader ? endColumn : 2);
      if (title.isEmpty) {
        skipped++;
        continue;
      }
      final page = start.isEmpty
          ? (await find(title)).firstOrNull
          : int.tryParse(start);
      final endPage = int.tryParse(end);
      if (page == null ||
          page < 1 ||
          page > document.pages.length ||
          end.isNotEmpty &&
              (endPage == null ||
                  endPage < page ||
                  endPage > document.pages.length)) {
        skipped++;
        continue;
      }
      candidates.add((title: title, page: page, endPage: endPage));
    }
    return (candidates: candidates, skipped: skipped);
  }
}
