import 'package:material_ui/material_ui.dart';

import 'score_library.dart';

typedef BookmarkDestination = ({String scoreId, int page, ScoreBookmark? item});

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({
    super.key,
    required this.library,
    required this.scoreId,
    required this.page,
    required this.pageCount,
  });

  final ScoreLibrary library;
  final String scoreId;
  final int page;
  final int pageCount;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  bool _saving = false;
  bool _showFlags = false;
  bool _allScores = false;

  Future<void> _toggleFlag(String scoreId, int page) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.library.updateScore(scoreId, (score) {
        final pages = score.flags.toSet();
        if (!pages.remove(page)) pages.add(page);
        return score.copyWith(flags: pages.toList()..sort());
      });
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
    final usedInSetlist =
        bookmark != null &&
        widget.library.isInSetlist(bookmark.selectionId(widget.scoreId));
    final saved = await showDialog<ScoreBookmark>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(bookmark == null ? 'New bookmark' : 'Edit bookmark'),
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
                initialValue: '$page',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Page'),
                onChanged: (value) =>
                    refresh(() => page = int.tryParse(value) ?? 0),
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
