import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;

import 'bookmark_import.dart';
import 'score_library.dart';
import 'score_metadata_screen.dart';

class MetadataCsvScreen extends StatefulWidget {
  const MetadataCsvScreen({super.key, required this.library});
  final ScoreLibrary library;

  @override
  State<MetadataCsvScreen> createState() => _MetadataCsvScreenState();
}

class _MetadataCsvScreenState extends State<MetadataCsvScreen> {
  bool _busy = false;
  String? _status;

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      _status = await action();
    } catch (error) {
      _status = error is FormatException
          ? error.message
          : 'Could not process the metadata file.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _export() async {
    final box = context.findRenderObject() as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final rows = [
      ['id', 'title', ...scoreMetadataFields.keys],
      for (final score in widget.library.recent)
        [
          score.id,
          score.title,
          for (final field in scoreMetadataFields.keys)
            score.metadata[field] ?? '',
        ],
    ];
    final csv = rows
        .map(
          (row) =>
              row.map((value) => '"${value.replaceAll('"', '""')}"').join(','),
        )
        .join('\r\n');
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(csv),
            name: 'EncoreSheets-metadata.csv',
            mimeType: 'text/csv',
          ),
        ],
        fileNameOverrides: ['EncoreSheets-metadata.csv'],
        sharePositionOrigin: anchor,
      ),
    );
    return null;
  }

  Future<String?> _import() async {
    final source = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Metadata table',
          extensions: ['csv', 'tsv'],
          mimeTypes: ['text/csv', 'text/tab-separated-values'],
          uniformTypeIdentifiers: [
            'public.comma-separated-values-text',
            'public.tab-separated-values-text',
          ],
        ),
      ],
    );
    if (source == null || !mounted) return null;
    final rows = parseBookmarkTable(
      await source.readAsString(),
      source.name.toLowerCase().endsWith('.tsv') ? '\t' : ',',
    );
    if (rows.isEmpty) throw const FormatException('The table is empty.');
    final header = rows.first.map((key) => key.toLowerCase()).toList();
    final idColumn = header.indexOf('id');
    final titleColumn = header.indexOf('title');
    if (idColumn < 0 && titleColumn < 0)
      throw const FormatException('Include an id or title column.');
    final edits = <String, ({String? title, Map<String, String> fields})>{};
    final scores = widget.library.recent;
    var skipped = 0;
    for (final row in rows.skip(1)) {
      String value(int index) =>
          index >= 0 && index < row.length ? row[index] : '';
      final title = value(titleColumn);
      final byTitle = scores
          .where((score) => score.title.toLowerCase() == title.toLowerCase())
          .toList();
      final score =
          widget.library.lookup(value(idColumn)) ??
          (byTitle.length == 1 ? byTitle.single : null);
      if (score == null || edits.containsKey(score.id)) {
        skipped++;
        continue;
      }
      edits[score.id] = (
        title: title.isEmpty ? null : title,
        fields: {
          for (final (index, field) in header.indexed)
            if (index < row.length && scoreMetadataFields.containsKey(field))
              field: row[index],
        },
      );
    }
    if (edits.isEmpty || !mounted)
      return 'No unique scores matched. $skipped rows skipped.';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Apply metadata import?'),
        content: Text(
          '${edits.length} scores matched. $skipped rows will be skipped. Empty fields in the table clear the corresponding values.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (accepted != true) return null;
    await widget.library.applyMetadataTable(edits);
    return 'Updated ${edits.length} scores. $skipped rows skipped.';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('CSV metadata')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Export a table to edit score metadata in a spreadsheet. Import matches scores by ID or unique title.',
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(_export),
              child: const Text('Export CSV'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _run(_import),
              child: const Text('Import CSV or TSV'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_status case final status?) Text(status),
          ],
        ),
      ),
    ),
  );
}
