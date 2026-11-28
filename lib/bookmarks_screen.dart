import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'bookmark_import.dart';
import 'score_library.dart';
import 'reader_deep_link.dart';
import 'share_reader_link.dart';

typedef BookmarkDestination = ({String scoreId, int page, ScoreBookmark? item});

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({
    super.key,
    required this.library,
    required this.scoreId,
    required this.page,
    required this.pageCount,
    required this.document,
  });

  final ScoreLibrary library;
  final String scoreId;
  final int page;
  final int pageCount;
  final PdfDocument document;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  bool _saving = false;
  bool _showFlags = false;
  bool _allScores = false;
  late final _index = BookmarkPageIndex(widget.document);

  Future<void> _importBookmarks(bool outline) async {
    if (_saving) return;
    setState(() => _saving = true);
    var candidates = <BookmarkCandidate>[];
    var skipped = 0;
    try {
      if (outline) {
        candidates = outlineBookmarks(
          await widget.document.loadOutline(),
          widget.pageCount,
        );
      } else {
        final file = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'Bookmark tables',
              extensions: ['csv', 'tsv'],
              mimeTypes: ['text/csv', 'text/tab-separated-values'],
              uniformTypeIdentifiers: [
                'public.comma-separated-values-text',
                'public.tab-separated-values-text',
              ],
            ),
          ],
        );
        if (file == null || !mounted) return;
        final result = await _index.importTable(
          await file.readAsString(),
          file.name.toLowerCase().endsWith('.tsv') ? '\t' : ',',
        );
        candidates = result.candidates;
        skipped = result.skipped;
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the bookmark source.')),
        );
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid bookmarks were found.')),
      );
      return;
    }
    final selected = candidates.toSet();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Review bookmarks'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (skipped > 0)
                  Text('$skipped rows could not be matched to valid pages.'),
                for (final item in candidates.toSet())
                  CheckboxListTile(
                    title: Text(item.title),
                    subtitle: Text(
                      item.endPage == null
                          ? 'Page ${item.page}'
                          : 'Pages ${item.page}–${item.endPage}',
                    ),
                    value: selected.contains(item),
                    onChanged: (checked) => refresh(() {
                      if (checked == true) {
                        selected.add(item);
                      } else {
                        selected.remove(item);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    await _change((existing) {
      final keys = existing
          .map(
            (item) => (
              title: item.title.toLowerCase(),
              page: item.page,
              endPage: item.endPage,
            ),
          )
          .toSet();
      final ids = existing.map((item) => item.id).toSet();
      var next = DateTime.now().microsecondsSinceEpoch;
      String newId() {
        while (!ids.add('$next')) {
          next++;
        }
        return '${next++}';
      }

      return [
        ...existing,
        for (final item in selected)
          if (keys.add((
            title: item.title.toLowerCase(),
            page: item.page,
            endPage: item.endPage,
          )))
            ScoreBookmark(
              newId(),
              item.title,
              item.page,
              endPage: item.endPage,
            ),
      ];
    });
  }

  Future<void> _toggleFlag(String scoreId, int page) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.library.togglePageFlag(scoreId, page);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update page flags.')),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit([ScoreBookmark? bookmark]) async {
    var title = bookmark?.title ?? '';
    var page = bookmark?.page ?? widget.page;
    var end = bookmark?.endPage?.toString() ?? '';
    var pageFieldVersion = 0;
    var lookingUp = false;
    final usedInSetlist =
        bookmark != null &&
        widget.library.isInSetlist(bookmark.selectionId(widget.scoreId));
    final saved = await showDialog<ScoreBookmark>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(bookmark == null ? 'New bookmark' : 'Edit bookmark'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
                onChanged: (value) => refresh(() => title = value),
              ),
              TextFormField(
                key: ValueKey(pageFieldVersion),
                initialValue: '$page',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Page'),
                onChanged: (value) =>
                    refresh(() => page = int.tryParse(value) ?? 0),
              ),
              TextButton(
                onPressed: lookingUp || title.trim().isEmpty
                    ? null
                    : () async {
                        refresh(() => lookingUp = true);
                        List<int> matches;
                        try {
                          matches = await _index.find(title);
                        } catch (_) {
                          matches = [];
                        }
                        if (!context.mounted) return;
                        refresh(() => lookingUp = false);
                        if (matches.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No matching PDF text found.'),
                            ),
                          );
                          return;
                        }
                        final selected = await showDialog<int>(
                          context: context,
                          builder: (choices) => SimpleDialog(
                            title: const Text('Matching pages'),
                            children: [
                              for (final match in matches)
                                SimpleDialogOption(
                                  onPressed: () =>
                                      Navigator.pop(choices, match),
                                  child: Text('Page $match'),
                                ),
                            ],
                          ),
                        );
                        if (!context.mounted || selected == null) return;
                        refresh(() {
                          page = selected;
                          pageFieldVersion++;
                        });
                      },
                child: Text(lookingUp ? 'Searching…' : 'Find page by title'),
              ),
              TextFormField(
                initialValue: end,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'End page (optional)',
                ),
                onChanged: (value) => refresh(() => end = value.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  title.trim().isEmpty ||
                      page < 1 ||
                      page > widget.pageCount ||
                      (usedInSetlist && end.isEmpty) ||
                      (end.isNotEmpty &&
                          ((int.tryParse(end) ?? 0) < page ||
                              (int.tryParse(end) ?? 0) > widget.pageCount))
                  ? null
                  : () => Navigator.pop(
                      context,
                      ScoreBookmark(
                        bookmark?.id ??
                            DateTime.now().microsecondsSinceEpoch.toString(),
                        title.trim(),
                        page,
                        endPage: int.tryParse(end),
                      ),
                    ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == null || !mounted) return;
    await _change(
      (items) => [
        for (final item in items)
          if (item.id != saved.id) item,
        saved,
      ],
    );
  }

  Future<void> _change(
    List<ScoreBookmark> Function(List<ScoreBookmark>) update,
  ) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.library.updateScore(
        widget.scoreId,
        (score) => score.copyWith(bookmarks: update(score.bookmarks)),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save bookmarks.')),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.library.lookup(widget.scoreId)!;
    final items = [...score.bookmarks]
      ..sort((a, b) => a.page.compareTo(b.page));
    return Scaffold(
      appBar: AppBar(
        title: Text(_showFlags ? 'Flags' : 'Bookmarks'),
        actions: [
          if (!_showFlags)
            PopupMenuButton<bool>(
              tooltip: 'Import bookmarks',
              enabled: !_saving,
              icon: const Icon(Icons.playlist_add),
              onSelected: _importBookmarks,
              itemBuilder: (_) => const [
                PopupMenuItem(value: true, child: Text('From PDF outline')),
                PopupMenuItem(value: false, child: Text('From CSV or TSV')),
              ],
            ),
          IconButton(
            tooltip: _showFlags ? 'Show bookmarks' : 'Show flags',
            onPressed: _saving
                ? null
                : () => setState(() => _showFlags = !_showFlags),
            icon: Icon(
              _showFlags ? Icons.bookmark_outline : Icons.flag_outlined,
            ),
          ),
          IconButton(
            tooltip: _showFlags
                ? score.flags.contains(widget.page)
                      ? 'Unflag current page'
                      : 'Flag current page'
                : 'Add bookmark',
            onPressed: _saving
                ? null
                : _showFlags
                ? () => _toggleFlag(score.id, widget.page)
                : _edit,
            icon: Icon(
              _showFlags
                  ? score.flags.contains(widget.page)
                        ? Icons.flag
                        : Icons.outlined_flag
                  : Icons.add,
            ),
          ),
        ],
      ),
      body: _showFlags
          ? _flags(score)
          : items.isEmpty
          ? const Center(child: Text('No bookmarks in this score.'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final bookmark = items[index];
                return ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text(bookmark.title),
                  subtitle: Text(
                    bookmark.isItem
                        ? 'Pages ${bookmark.page}–${bookmark.endPage}'
                        : 'Page ${bookmark.page}',
                  ),
                  onTap: _saving
                      ? null
                      : () => Navigator.pop(context, (
                          scoreId: score.id,
                          page: bookmark.page,
                          item: bookmark.isItem ? bookmark : null,
                        )),
                  trailing: PopupMenuButton<String>(
                    enabled: !_saving,
                    onSelected: (action) {
                      if (action == 'edit') {
                        _edit(bookmark);
                      } else if (action == 'link') {
                        copyReaderLink(
                          context,
                          ReaderLinkTarget.bookmark,
                          bookmark.selectionId(score.id),
                        );
                      } else {
                        _change(
                          (items) => items
                              .where((item) => item.id != bookmark.id)
                              .toList(),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                        value: 'link',
                        child: Text('Copy bookmark link'),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        enabled: !widget.library.isInSetlist(
                          bookmark.selectionId(widget.scoreId),
                        ),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _flags(ScoreEntry current) {
    final entries = [
      for (final score in _allScores ? widget.library.recent : [current])
        for (final page in score.flags) (score, page),
    ];
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Show all scores'),
          value: _allScores,
          onChanged: (enabled) => setState(() => _allScores = enabled),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No flagged pages.'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final (score, page) = entries[index];
                    return ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: Text('Page $page'),
                      subtitle: _allScores ? Text(score.title) : null,
                      onTap: () => Navigator.pop(context, (
                        scoreId: score.id,
                        page: page,
                        item: null as ScoreBookmark?,
                      )),
                      trailing: IconButton(
                        tooltip: 'Remove flag',
                        icon: const Icon(Icons.clear),
                        onPressed: _saving
                            ? null
                            : () => _toggleFlag(score.id, page),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
