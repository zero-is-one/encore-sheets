import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_rearrange.dart';
import 'score_library.dart';

class PdfRearrangeScreen extends StatefulWidget {
  const PdfRearrangeScreen({
    super.key,
    required this.library,
    required ScoreEntry this.score,
  }) : scan = null;

  const PdfRearrangeScreen.scanned({
    super.key,
    required this.library,
    required XFile this.scan,
  }) : score = null;

  final ScoreLibrary library;
  final ScoreEntry? score;
  final XFile? scan;

  @override
  State<PdfRearrangeScreen> createState() => _PdfRearrangeScreenState();
}

class _PdfRearrangeScreenState extends State<PdfRearrangeScreen> {
  final _documents = <PdfDocument>[];
  final _pages = <({Object key, EditedPdfPage page, String label})>[];
  final _selected = <Object>{};
  bool _busy = true;
  bool _grid = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file =
          widget.scan ??
          await widget.library.storage.openScore(widget.score!.id);
      await _append(file, original: true);
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not open this PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final document in _documents) {
      unawaited(document.dispose());
    }
    super.dispose();
  }

  Future<void> _append(XFile file, {required bool original}) async {
    final document = await openRearrangeDocument(file);
    if (!mounted) {
      await document.dispose();
      return;
    }
    setState(() {
      _documents.add(document);
      for (final page in document.pages) {
        _pages.add((
          key: Object(),
          page: EditedPdfPage(
            page,
            originalPage: original ? page.pageNumber : null,
          ),
          label: original
              ? 'Page ${page.pageNumber}'
              : '${file.name} · Page ${page.pageNumber}',
        ));
      }
    });
  }

  Future<void> _insert() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'PDF scores',
            extensions: ['pdf'],
            mimeTypes: ['application/pdf'],
            uniformTypeIdentifiers: ['com.adobe.pdf'],
          ),
        ],
      );
      if (file != null && mounted) await _append(file, original: false);
    } catch (_) {
      if (mounted)
        setState(() => _message = 'Could not insert pages from this PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({required bool replace}) async {
    if (_busy || _pages.isEmpty) return;
    if (replace) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Replace this score?'),
          content: const Text(
            'Setlists will use the rearranged copy. The previous version can be recovered from Recently updated.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (!mounted || approved != true) return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final original = widget.score;
      final pages = _pages.map((row) => row.page).toList();
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 19)
          .replaceAll(':', '-')
          .replaceAll('T', ' ');
      final title = original == null
          ? 'Scan $stamp'
          : replace
          ? original.title
          : '${original.title} (rearranged)';
      final file = await writeRearrangedPdf('$title.pdf', pages);
      if (original == null) {
        final (score, _) = await widget.library.import(file);
        if (mounted) Navigator.pop(context, score);
        return;
      }
      final annotations = await widget.library.readInk(original.id);
      final remapped = remapScorePages(original, annotations, pages);
      final (score, _) = await widget.library.import(
        file,
        template: remapped.score,
        annotations: remapped.annotations,
        replace: replace,
      );
      if (mounted) Navigator.pop(context, score);
    } catch (_) {
      if (mounted)
        setState(() => _message = 'Could not save the rearranged PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _editPage(int index, String action) {
    final row = _pages[index];
    setState(() {
      switch (action) {
        case 'duplicate':
          _pages.insert(index + 1, (
            key: Object(),
            page: row.page,
            label: row.label,
          ));
        case 'rotate':
          _pages[index] = (
            key: row.key,
            page: row.page.rotate(),
            label: row.label,
          );
        case 'remove':
          _selected.remove(row.key);
          _pages.removeAt(index);
        case 'earlier':
          _pages.insert(index - 1, _pages.removeAt(index));
        case 'later':
          _pages.insert(index + 1, _pages.removeAt(index));
      }
    });
  }

  Widget _pagePreview(EditedPdfPage edit, double dpi) => RotatedBox(
    quarterTurns: edit.rotation,
    child: PdfPageView(
      document: edit.page.document,
      pageNumber: edit.page.pageNumber,
      maximumDpi: dpi,
    ),
  );

  Widget _pageActions(int index) => PopupMenuButton<String>(
    enabled: !_busy,
    tooltip: 'Page actions',
    onSelected: (action) => _editPage(index, action),
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
      const PopupMenuItem(value: 'rotate', child: Text('Rotate 90° clockwise')),
      if (_grid) ...[
        PopupMenuItem(
          value: 'earlier',
          enabled: index > 0,
          child: const Text('Move earlier'),
        ),
        PopupMenuItem(
          value: 'later',
          enabled: index + 1 < _pages.length,
          child: const Text('Move later'),
        ),
      ],
      PopupMenuItem(
        value: 'remove',
        enabled: _pages.length > 1,
        child: const Text('Remove'),
      ),
    ],
  );

  Widget _pageGrid() => GridView.builder(
    padding: const EdgeInsets.all(12),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 180,
      mainAxisExtent: 186,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    itemCount: _pages.length,
    itemBuilder: (_, index) {
      final row = _pages[index];
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy
              ? null
              : () => setState(() {
                  if (!_selected.remove(row.key)) _selected.add(row.key);
                }),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _pagePreview(row.page, 56),
                ),
              ),
              Row(
                children: [
                  if (_selected.contains(row.key)) const Icon(Icons.check),
                  Expanded(
                    child: Text(
                      '${index + 1} · ${row.label}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _pageActions(index),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.scan == null ? 'Rearrange pages' : 'Review scanned pages',
        ),
        actions: [
          IconButton(
            tooltip: _grid ? 'List view' : 'Grid view',
            onPressed: _busy
                ? null
                : () => setState(() {
                    _grid = !_grid;
                    _selected.clear();
                  }),
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : _insert,
                  child: const Text('Insert PDF'),
                ),
                TextButton(
                  onPressed: _busy || _pages.isEmpty
                      ? null
                      : () => _save(replace: false),
                  child: Text(
                    widget.scan == null ? 'Save as copy' : 'Save scanned score',
                  ),
                ),
                if (widget.scan == null)
                  TextButton(
                    onPressed: _busy || _pages.isEmpty
                        ? null
                        : () => _save(replace: true),
                    child: const Text('Replace score'),
                  ),
                if (_grid && _selected.isNotEmpty)
                  TextButton(
                    onPressed: _busy || _selected.length >= _pages.length
                        ? null
                        : () => setState(() {
                            _pages.removeWhere(
                              (row) => _selected.contains(row.key),
                            );
                            _selected.clear();
                          }),
                    child: Text('Remove selected (${_selected.length})'),
                  ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message case final message?) Text(message),
            Expanded(
              child: _grid
                  ? _pageGrid()
                  : ReorderableListView.builder(
                      itemCount: _pages.length,
                      buildDefaultDragHandles: false,
                      onReorderItem: (oldIndex, newIndex) {
                        if (_busy) return;
                        setState(
                          () => _pages.insert(
                            newIndex,
                            _pages.removeAt(oldIndex),
                          ),
                        );
                      },
                      itemBuilder: (context, index) {
                        final row = _pages[index];
                        return ListTile(
                          key: ObjectKey(row.key),
                          leading: ReorderableDragStartListener(
                            index: index,
                            enabled: !_busy,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                          title: Text(
                            row.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'Position ${index + 1} · ${row.page.rotation * 90}°',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 46,
                                height: 56,
                                child: _pagePreview(row.page, 32),
                              ),
                              _pageActions(index),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
