import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;

import 'score_library.dart';
import 'app_localization.dart';
import 'score_clipboard.dart';
import 'reader_deep_link.dart';
import 'share_reader_link.dart';
import 'program_duration.dart';
import 'setlist_order.dart';
import 'setlist_share.dart';

enum _SetlistAction {
  edit,
  duplicate,
  playInOrder,
  earlier,
  later,
  share,
  link,
}

String _durationText(ScoreLibrary library, Iterable<String> selections) {
  final estimate = library.estimateSetlistDuration(selections);
  final parts = [
    if (estimate.total > Duration.zero)
      '${formatProgramDuration(estimate.total)} estimated',
    if (estimate.missing > 0) '${estimate.missing} without durations',
  ];
  return parts.join(' · ');
}

typedef SetlistPlayback = ({Setlist setlist, int startIndex});

class SetlistsScreen extends StatefulWidget {
  const SetlistsScreen({
    super.key,
    required this.library,
    this.allowTransfers = true,
  });

  final ScoreLibrary library;
  final bool allowTransfers;

  @override
  State<SetlistsScreen> createState() => _SetlistsScreenState();
}

class _SetlistsScreenState extends State<SetlistsScreen> {
  SetlistOrder _sort = SetlistOrder.manual;
  bool _transferring = false;

  bool _selectingSetlists = false;
  final _selectedSetlists = <String>{};

  Future<void> _duplicateSelection() => _transfer(() async {
    await widget.library.duplicateSetlists(_selectedSetlists);
    if (mounted) {
      setState(() {
        _selectedSetlists.clear();
        _selectingSetlists = false;
      });
    }
  }, 'Could not duplicate the selected setlists.');

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
        list.scores.every((id) {
          final item = widget.library.lookupSelection(id);
          return item != null && item.$1.validUntil == null;
        });
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
    await Navigator.of(context, rootNavigator: true).push<void>(
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
    Navigator.pop(context, (
      setlist: list.copyWith(scores: items),
      startIndex: 0,
    ));
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

  Future<void> _inspect(Setlist list) async {
    final play = await Navigator.of(context).push<SetlistPlayback>(
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, refresh) {
            final current = widget.library.setlists.firstWhere(
              (item) => item.id == list.id,
            );
            return Scaffold(
              appBar: AppBar(
                title: Text(current.name),
                actions: [
                  IconButton(
                    tooltip: 'Edit setlist',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      await _edit(current);
                      if (context.mounted) refresh(() {});
                    },
                  ),
                  TextButton.icon(
                    onPressed: current.scores.isEmpty
                        ? null
                        : () => Navigator.pop(context, (
                            setlist: current,
                            startIndex: 0,
                          )),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                ],
              ),
              body: ListView(
                children: [
                  if (current.notes.isNotEmpty)
                    ListTile(subtitle: Text(current.notes)),
                  if (current.scores.isEmpty)
                    const ListTile(
                      title: Text(
                        'No scores yet. Choose Edit setlist to add one.',
                      ),
                    ),
                  for (final (index, id) in current.scores.indexed)
                    ListTile(
                      leading: Text('${index + 1}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        tooltip: 'Play from item ${index + 1}',
                        onPressed: widget.library.lookupSelection(id) == null
                            ? null
                            : () => Navigator.pop(context, (
                                setlist: current,
                                startIndex: index,
                              )),
                      ),
                      title: Text(switch (widget.library.lookupSelection(id)) {
                        (final score, final bookmark) =>
                          bookmark?.title ?? score.title,
                        null => current.placeholders[id] ?? 'Missing score',
                      }),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    if (!mounted) return;
    if (play != null)
      Navigator.pop(context, play);
    else
      setState(() {});
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
    onTap: () => _inspect(list),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (list.scores.isNotEmpty)
          IconButton(
            tooltip: 'Play ${list.name}',
            onPressed: () =>
                Navigator.pop(context, (setlist: list, startIndex: 0)),
            icon: const Icon(Icons.play_arrow),
          ),
        PopupMenuButton<_SetlistAction>(
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
              case _SetlistAction.link:
                copyReaderLink(context, ReaderLinkTarget.setlist, list.id);
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
            if (widget.allowTransfers)
              PopupMenuItem(
                value: _SetlistAction.share,
                enabled: !_transferring,
                child: const Text('Share setlist'),
              ),
            if (widget.allowTransfers)
              const PopupMenuItem(
                value: _SetlistAction.link,
                child: Text('Copy setlist link'),
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
        for (final (index, list) in group.indexed)
          if (_selectingSetlists)
            CheckboxListTile(
              title: Text(list.name),
              value: _selectedSetlists.contains(list.id),
              onChanged: _transferring
                  ? null
                  : (selected) {
                      setState(() {
                        if (selected == true) {
                          _selectedSetlists.add(list.id);
                        } else {
                          _selectedSetlists.remove(list.id);
                        }
                      });
                    },
            )
          else
            _row(list, group, index),
      ];
    }

    final folders = {
      for (final list in lists)
        if (list.folder.isNotEmpty) list.folder,
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Scaffold(
      appBar: AppBar(
        title: Text(ReaderText.setlists.of(context)),
        actions: [
          if (_selectingSetlists)
            TextButton(
              onPressed: _selectedSetlists.isEmpty || _transferring
                  ? null
                  : _duplicateSelection,
              child: Text('Duplicate ${_selectedSetlists.length}'),
            ),
          IconButton(
            tooltip: _selectingSetlists
                ? 'Cancel setlist selection'
                : 'Select setlists',
            icon: Icon(_selectingSetlists ? Icons.close : Icons.checklist),
            onPressed: _transferring || lists.isEmpty
                ? null
                : () => setState(() {
                    _selectingSetlists = !_selectingSetlists;
                    _selectedSetlists.clear();
                  }),
          ),
          if (widget.library.storage.persistent && widget.allowTransfers)
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
  String _libraryQuery = '';
  Object? _replacement;

  Future<void> _pickFolder() async {
    final folders =
        widget.library.setlists
            .map((list) => list.folder)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final folder = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Choose setlist folder'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, ''),
            child: const Text('No folder'),
          ),
          for (final name in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (mounted && folder != null) _folder.text = folder;
  }

  void _insertSelection(String id, {Object? replace}) {
    if (_saving) return;
    setState(() {
      final index = _scores.indexWhere((row) => row.key == replace);
      if (index == -1) {
        if (replace == null) _scores.add((key: Object(), id: id));
      } else {
        _scores[index] = (key: _scores[index].key, id: id);
      }
      _replacement = null;
    });
  }

  void _clipboardStatus(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copySelection(({Object key, String id}) row, bool move) async {
    final selected = widget.library.lookupSelection(row.id);
    if (selected == null) return;
    try {
      await writeScoreClipboard((
        scope: 'library',
        id: row.id,
        name: selected.$2?.title ?? selected.$1.title,
        move: move,
      ));
      if (!mounted) return;
      if (move) {
        setState(() {
          if (_replacement == row.key) _replacement = null;
          _scores.removeWhere((item) => item.key == row.key);
        });
      }
      _clipboardStatus(move ? 'Score cut from this draft.' : 'Score copied.');
    } catch (_) {
      _clipboardStatus('Could not copy this selection.');
    }
  }

  Future<void> _pasteSelection() async {
    try {
      final selected = await readScoreClipboard();
      if (selected == null ||
          selected.scope != 'library' ||
          widget.library.lookupSelection(selected.id) == null) {
        _clipboardStatus('Copy a score or setlist item first.');
        return;
      }
      if (!mounted || _saving) return;
      setState(() => _scores.add((key: Object(), id: selected.id)));
      _clipboardStatus('Score pasted into this draft.');
    } catch (_) {
      _clipboardStatus('Could not paste this selection.');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _folder.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _add([int? replaceAt]) async {
    final replacement = replaceAt == null ? null : _scores[replaceAt].key;
    final selection = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => widget.library.recent.isEmpty
          ? const Center(
              child: Text('Import a PDF in the score library first.'),
            )
          : _scorePicker('', (id) => Navigator.pop(context, id)),
    );
    if (!mounted || selection == null) return;
    _insertSelection(selection, replace: replacement);
  }

  Widget _scorePicker(String query, ValueChanged<String> select) {
    final matches = <({String id, String title, String? score})>[];
    for (final score in widget.library.recent) {
      final all = [score.title, ...score.metadata.values];
      final match = all.any((value) => value.toLowerCase().contains(query));
      if (match) matches.add((id: score.id, title: score.title, score: null));
      for (final bookmark in score.bookmarks.where((item) => item.isItem)) {
        if (match || bookmark.title.toLowerCase().contains(query)) {
          matches.add((
            id: bookmark.selectionId(score.id),
            title: bookmark.title,
            score: score.title,
          ));
        }
      }
    }
    if (matches.isEmpty)
      return const Center(child: Text('No matching scores.'));
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (_, index) {
        final row = matches[index];
        return ListTile(
          leading: Icon(
            row.score == null
                ? Icons.description_outlined
                : Icons.bookmark_outline,
          ),
          title: Text(row.title),
          subtitle: row.score == null ? null : Text(row.score!),
          onTap: _saving ? null : () => select(row.id),
        );
      },
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    final id = widget.initial?.id ?? ScoreLibrary.newRecordId();
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
          decoration: InputDecoration(
            labelText: 'Folder (optional)',
            suffixIcon: IconButton(
              tooltip: 'Choose existing folder',
              onPressed: _saving ? null : _pickFolder,
              icon: const Icon(Icons.folder_open),
            ),
          ),
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
        const SizedBox(height: 20),
        Text('Score order', style: Theme.of(context).textTheme.titleMedium),
        if (_scores.isNotEmpty)
          Text(_durationText(widget.library, _scores.map((row) => row.id))),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final queue = ReorderableListView.builder(
            header: _details(),
            footer: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                children: [
                  if (!wide)
                    FilledButton.icon(
                      onPressed: _saving ? null : _add,
                      icon: const Icon(Icons.add),
                      label: const Text('Add score'),
                    ),
                  TextButton.icon(
                    onPressed: _saving ? null : _pasteSelection,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Paste score'),
                  ),
                ],
              ),
            ),
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
                (final score, final bookmark) => bookmark?.title ?? score.title,
                null =>
                  widget.initial?.placeholders[_scores[index].id] ??
                      'Missing score',
              }),
              subtitle:
                  widget.initial?.placeholders.containsKey(_scores[index].id) ==
                      true
                  ? const Text('Tap to choose a score')
                  : null,
              selected: wide && _replacement == _scores[index].key,
              onTap: _saving
                  ? null
                  : () {
                      if (!wide) {
                        _add(index);
                        return;
                      }
                      final key = _scores[index].key;
                      setState(
                        () => _replacement = _replacement == key ? null : key,
                      );
                    },
              trailing: PopupMenuButton<String>(
                enabled: !_saving,
                tooltip: 'Setlist item actions',
                onSelected: (action) {
                  final row = _scores[index];
                  if (action == 'remove') {
                    setState(() {
                      if (_replacement == row.key) _replacement = null;
                      _scores.removeAt(index);
                    });
                  } else {
                    _copySelection(row, action == 'cut');
                  }
                },
                itemBuilder: (_) => [
                  if (widget.library.lookupSelection(_scores[index].id) !=
                      null) ...[
                    const PopupMenuItem(
                      value: 'copy',
                      child: Text('Copy score'),
                    ),
                    const PopupMenuItem(
                      value: 'cut',
                      child: Text('Cut from setlist'),
                    ),
                  ],
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove score'),
                  ),
                ],
              ),
            ),
          );
          if (!wide)
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: queue,
              ),
            );
          return Row(
            children: [
              Expanded(child: queue),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Score library',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_replacement != null)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _replacement = null),
                              child: const Text('Cancel replacement'),
                            )
                          else
                            const Text('Tap a score to add it to the setlist.'),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Search scores',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (value) => setState(
                              () => _libraryQuery = value.trim().toLowerCase(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _scorePicker(
                        _libraryQuery,
                        (id) => _insertSelection(id, replace: _replacement),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
