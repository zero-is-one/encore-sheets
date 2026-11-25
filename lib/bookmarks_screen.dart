import 'package:material_ui/material_ui.dart';

import 'score_library.dart';

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

  Future<void> _edit([ScoreBookmark? bookmark]) async {
    var title = bookmark?.title ?? '';
    var page = bookmark?.page ?? widget.page;
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  title.trim().isEmpty || page < 1 || page > widget.pageCount
                  ? null
                  : () => Navigator.pop(
                      context,
                      ScoreBookmark(
                        bookmark?.id ??
                            DateTime.now().microsecondsSinceEpoch.toString(),
                        title.trim(),
                        page,
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
        title: const Text('Bookmarks'),
        actions: [
          IconButton(
            tooltip: 'Add bookmark',
            onPressed: _saving ? null : _edit,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('No bookmarks in this score.'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final bookmark = items[index];
                return ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text(bookmark.title),
                  subtitle: Text('Page ${bookmark.page}'),
                  onTap: _saving
                      ? null
                      : () => Navigator.pop(context, bookmark),
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
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'remove', child: Text('Remove')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
