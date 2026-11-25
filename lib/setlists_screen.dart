import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;

import 'score_library.dart';
import 'program_duration.dart';
import 'setlist_order.dart';
import 'setlist_share.dart';

enum _SetlistAction { edit, duplicate, playInOrder, earlier, later, share }

String _durationText(ScoreLibrary library, Iterable<String> selections) {
  final estimate = library.estimateSetlistDuration(selections);
  final parts = [
    if (estimate.total > Duration.zero)
      '${formatProgramDuration(estimate.total)} estimated',
    if (estimate.missing > 0) '${estimate.missing} without durations',
  ];
  return parts.join(' · ');
}

class SetlistsScreen extends StatefulWidget {
  const SetlistsScreen({super.key, required this.library});

  final ScoreLibrary library;

  @override
  State<SetlistsScreen> createState() => _SetlistsScreenState();
}

class _SetlistsScreenState extends State<SetlistsScreen> {
  SetlistOrder _sort = SetlistOrder.manual;
  bool _transferring = false;

  Future<void> _transfer(Future<void> Function() work, String failure) async {
    if (_transferring) return;
    setState(() => _transferring = true);
    try {
      await work();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _importPackage() => _transfer(() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'EncoreSheets setlist packages',
          extensions: ['zip'],
          mimeTypes: ['application/zip'],
          uniformTypeIdentifiers: ['public.zip-archive'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    await widget.library.restoreSetlistPackage(file);
  }, 'Could not import the setlist package.');

  Future<void> _share(Setlist list) => _transfer(() async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final canCombine =
        list.scores.isNotEmpty &&
        list.scores.every((id) => widget.library.lookupSelection(id) != null);
    final format = await showDialog<SetlistShareFormat>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Share setlist'),
        children: [
          for (final format in SetlistShareFormat.values)
            if (widget.library.storage.persistent ||
                format == SetlistShareFormat.text ||
                format == SetlistShareFormat.pdf)
              SimpleDialogOption(
                onPressed: format == SetlistShareFormat.pdf && !canCombine
                    ? null
                    : () => Navigator.pop(dialog, format),
                child: Text(format.label),
              ),
        ],
      ),
    );
    if (!mounted || format == null) return;
    final output = await exportSetlist(widget.library, list, format);
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [output],
        fileNameOverrides: [output.name],
        sharePositionOrigin: origin,
      ),
    );
  }, 'Could not share the setlist.');

  Future<void> _edit([Setlist? initial]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            _SetlistEditor(library: widget.library, initial: initial),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _duplicate(Setlist original) async {
    try {
      await widget.library.duplicateSetlist(original);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not duplicate the setlist.')),
        );
      }
    }
  }

  Future<void> _choosePlayOrder(Setlist list) async {
    final order = await showDialog<SetlistOrder>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text('Play ${list.name}'),
        children: [
          for (final order in SetlistOrder.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, order),
              child: Text(order.label),
            ),
        ],
      ),
    );
    if (!mounted || order == null) return;
    final items = orderSetlistItems(
      list.scores,
      order,
      title: (id) {
        final found = widget.library.lookupSelection(id);
        return found?.$2?.title ?? found?.$1.title ?? '';
      },
      lastPlayed: (id) => widget.library.lastSetlistPlay(list.id, id),
    );
    Navigator.pop(context, list.copyWith(scores: items));
  }

  Future<void> _move(Setlist current, Setlist other) async {
    try {
      await widget.library.moveSetlist(current.id, other.id);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not move the setlist.')),
        );
    }
  }

  Widget _row(Setlist list, List<Setlist> group, int index) => ListTile(
    leading: const Icon(Icons.queue_music),
    title: Text(list.name),
    subtitle: Text(
      [
        '${list.scores.length} scores',
        if (list.label.isNotEmpty) list.label,
        if (list.scores.isNotEmpty) _durationText(widget.library, list.scores),
        if (list.notes.isNotEmpty) list.notes,
      ].join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: list.scores.isEmpty
        ? () => _edit(list)
        : () => Navigator.pop(context, list),
    trailing: PopupMenuButton<_SetlistAction>(
      tooltip: 'Options for ${list.name}',
      onSelected: (action) {
        switch (action) {
          case _SetlistAction.edit:
            _edit(list);
          case _SetlistAction.duplicate:
            _duplicate(list);
          case _SetlistAction.playInOrder:
            _choosePlayOrder(list);
          case _SetlistAction.earlier:
            _move(list, group[index - 1]);
          case _SetlistAction.later:
            _move(list, group[index + 1]);
          case _SetlistAction.share:
            _share(list);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _SetlistAction.edit,
          child: Text('Edit setlist'),
        ),
        const PopupMenuItem(
          value: _SetlistAction.duplicate,
          child: Text('Duplicate setlist'),
        ),
        PopupMenuItem(
          value: _SetlistAction.playInOrder,
          enabled: list.scores.isNotEmpty,
          child: const Text('Choose play order'),
        ),
        PopupMenuItem(
          value: _SetlistAction.share,
          enabled: !_transferring,
          child: const Text('Share setlist'),
        ),
        if (_sort == SetlistOrder.manual) ...[
          PopupMenuItem(
            value: _SetlistAction.earlier,
            enabled: index > 0,
            child: const Text('Move earlier'),
          ),
          PopupMenuItem(
            value: _SetlistAction.later,
            enabled: index + 1 < group.length,
            child: const Text('Move later'),
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final lists = orderSetlistItems(
      widget.library.setlists,
      _sort,
      title: (list) => list.name,
      lastPlayed: (list) => widget.library.lastSetlistPlay(list.id),
    );
    final grouped = <String, List<Setlist>>{};
    for (final list in lists) {
      (grouped[list.folder] ??= []).add(list);
    }
    List<Widget> rowsFor(String folder) {
      final group = grouped[folder] ?? [];
      return [
        for (final (index, list) in group.indexed) _row(list, group, index),
      ];
    }

    final folders = {
      for (final list in lists)
        if (list.folder.isNotEmpty) list.folder,
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setlists'),
        actions: [
          if (widget.library.storage.persistent)
            IconButton(
              tooltip: 'Import setlist package',
              onPressed: _transferring ? null : _importPackage,
              icon: const Icon(Icons.file_open_outlined),
            ),
          PopupMenuButton<SetlistOrder>(
            tooltip: 'Sort setlists',
            icon: const Icon(Icons.sort),
            onSelected: (order) => setState(() => _sort = order),
            itemBuilder: (_) => [
              for (final order in SetlistOrder.values)
                if (order != SetlistOrder.shuffle)
                  CheckedPopupMenuItem(
                    value: order,
                    checked: _sort == order,
                    child: Text(order.label),
                  ),
            ],
          ),
          TextButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.add),
            label: const Text('New setlist'),
          ),
        ],
      ),
      body: lists.isEmpty
          ? const Center(
              child: Text('Create a setlist for your next performance.'),
            )
          : ListView(
              children: [
                for (final folder in folders)
                  ExpansionTile(
                    key: PageStorageKey(folder),
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(folder),
                    children: rowsFor(folder),
                  ),
                ...rowsFor(''),
              ],
            ),
    );
  }
}

class _SetlistEditor extends StatefulWidget {
  const _SetlistEditor({required this.library, this.initial});

  final ScoreLibrary library;
  final Setlist? initial;

  @override
  State<_SetlistEditor> createState() => _SetlistEditorState();
}

class _SetlistEditorState extends State<_SetlistEditor> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _folder = TextEditingController(
    text: widget.initial?.folder ?? '',
  );
  late final _label = TextEditingController(text: widget.initial?.label ?? '');
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');
  late final _scores = [
    for (final id in widget.initial?.scores ?? <String>[])
      (key: Object(), id: id),
  ];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _folder.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _add([int? replaceAt]) async {
    final scores = widget.library.recent;
    final selection = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => scores.isEmpty
          ? const Center(
              child: Text('Import a PDF in the score library first.'),
            )
          : ListView(
              children: [
                for (final score in scores) ...[
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(score.title),
                    onTap: () => Navigator.pop(context, score.id),
                  ),
                  for (final bookmark in score.bookmarks.where(
                    (item) => item.isItem,
                  ))
                    ListTile(
                      leading: const Icon(Icons.bookmark_outline),
                      title: Text(bookmark.title),
                      subtitle: Text(score.title),
                      onTap: () => Navigator.pop(
                        context,
                        bookmark.selectionId(score.id),
                      ),
                    ),
                ],
              ],
            ),
    );
    if (!mounted || selection == null) return;
    setState(() {
      if (replaceAt == null) {
        _scores.add((key: Object(), id: selection));
      } else {
        _scores[replaceAt] = (key: _scores[replaceAt].key, id: selection);
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    final id =
        widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    setState(() => _saving = true);
    try {
      await widget.library.saveSetlist(
        Setlist(
          id,
          name,
          _scores.map((item) => item.id),
          folder: _folder.text.trim(),
          label: _label.text.trim(),
          notes: _notes.text.trim(),
          placeholders: {
            for (final item in _scores)
              if (widget.initial?.placeholders[item.id] case final name?)
                item.id: name,
          },
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the setlist.')),
      );
    }
  }

  Widget _details() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Setlist name'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _folder,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Folder (optional)'),
        ),
        TextField(
          controller: _label,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Program label'),
        ),
        TextField(
          controller: _notes,
          enabled: !_saving,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Program notes'),
        ),
        if (_scores.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _durationText(widget.library, _scores.map((row) => row.id)),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.initial == null ? 'New setlist' : 'Edit setlist'),
      actions: [
        TextButton(
          onPressed: _name.text.trim().isEmpty || _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              header: _details(),
              buildDefaultDragHandles: false,
              itemCount: _scores.length,
              onReorderItem: (oldIndex, newIndex) {
                if (_saving) return;
                setState(() {
                  _scores.insert(newIndex, _scores.removeAt(oldIndex));
                });
              },
              itemBuilder: (context, index) => ListTile(
                key: ObjectKey(_scores[index].key),
                leading: ReorderableDragStartListener(
                  index: index,
                  enabled: !_saving,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
                title: Text(switch (widget.library.lookupSelection(
                  _scores[index].id,
                )) {
                  (final score, final bookmark) =>
                    bookmark?.title ?? score.title,
                  null =>
                    widget.initial?.placeholders[_scores[index].id] ??
                        'Missing score',
                }),
                subtitle:
                    widget.initial?.placeholders.containsKey(
                          _scores[index].id,
                        ) ==
                        true
                    ? const Text('Tap to choose a score')
                    : null,
                onTap: _saving ? null : () => _add(index),
                trailing: IconButton(
                  tooltip: 'Remove score',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _scores.removeAt(index)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _saving ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Add score'),
            ),
          ),
        ],
      ),
    ),
  );
}
