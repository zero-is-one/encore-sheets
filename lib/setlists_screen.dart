import 'package:material_ui/material_ui.dart';

import 'score_library.dart';

class SetlistsScreen extends StatefulWidget {
  const SetlistsScreen({super.key, required this.library});

  final ScoreLibrary library;

  @override
  State<SetlistsScreen> createState() => _SetlistsScreenState();
}

class _SetlistsScreenState extends State<SetlistsScreen> {
  Future<void> _edit([Setlist? initial]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            _SetlistEditor(library: widget.library, initial: initial),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lists = widget.library.setlists;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setlists'),
        actions: [
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
                for (final list in lists)
                  ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: Text(list.name),
                    subtitle: Text('${list.scores.length} scores'),
                    onTap: list.scores.isEmpty
                        ? () => _edit(list)
                        : () => Navigator.pop(context, list),
                    trailing: IconButton(
                      tooltip: 'Edit ${list.name}',
                      onPressed: () => _edit(list),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
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
  late final _scores = [
    for (final id in widget.initial?.scores ?? <String>[])
      (key: Object(), id: id),
  ];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final scores = widget.library.recent;
    final score = await showModalBottomSheet<ScoreEntry>(
      context: context,
      useSafeArea: true,
      builder: (context) => scores.isEmpty
          ? const Center(
              child: Text('Import a PDF in the score library first.'),
            )
          : ListView(
              children: [
                for (final score in scores)
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(score.title),
                    onTap: () => Navigator.pop(context, score),
                  ),
              ],
            ),
    );
    if (mounted && score != null)
      setState(() => _scores.add((key: Object(), id: score.id)));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    final id =
        widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    setState(() => _saving = true);
    try {
      await widget.library.saveSetlist(
        Setlist(id, name, _scores.map((item) => item.id)),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _name,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Setlist name'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
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
                title: Text(
                  widget.library.lookup(_scores[index].id)?.title ??
                      'Missing score',
                ),
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
