import 'package:material_ui/material_ui.dart';

import 'library_score_preview.dart';
import 'score_library.dart';

const scoreMetadataFields = {
  'composer': 'Composers',
  'genre': 'Genres',
  'label': 'Labels',
  'tags': 'Tags',
  'rating': 'Rating',
  'difficulty': 'Difficulty',
  'reference': 'Reference',
  'time': 'Time signature',
  'duration': 'Duration',
  'tempo': 'Tempo',
  'key': 'Key',
};

typedef ScoreMetadataEdit = ({
  String title,
  Map<String, String> fields,
  Set<String> setlists,
  Set<String> libraries,
  int? openPage,
});

Future<ScoreMetadataEdit?> editScoreMetadata(
  BuildContext context,
  ScoreEntry score, {
  Future<Map<String, String>> Function()? loadPdfInfo,
  Future<ScorePreviewPage?> Function(int page)? preview,
  required List<Setlist> setlists,
  required List<String> libraries,
  VoidCallback? onMidi,
  VoidCallback? onAudio,
}) => showDialog(
  context: context,
  builder: (_) => _ScoreMetadataDialog(
    score: score,
    loadPdfInfo: loadPdfInfo,
    preview: preview,
    setlists: setlists,
    libraries: libraries,
    onMidi: onMidi,
    onAudio: onAudio,
  ),
);

enum _MetadataSection {
  properties('Properties', Icons.info_outline),
  setlists('Setlists', Icons.queue_music),
  audio('Audio', Icons.headphones_outlined),
  midi('MIDI', Icons.settings_input_component),
  libraries('Libraries', Icons.library_books_outlined);

  const _MetadataSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _ScoreMetadataDialog extends StatefulWidget {
  const _ScoreMetadataDialog({
    required this.score,
    this.loadPdfInfo,
    this.preview,
    required this.setlists,
    required this.libraries,
    this.onMidi,
    this.onAudio,
  });

  final ScoreEntry score;
  final Future<Map<String, String>> Function()? loadPdfInfo;
  final Future<ScorePreviewPage?> Function(int page)? preview;
  final List<Setlist> setlists;
  final List<String> libraries;
  final VoidCallback? onMidi;
  final VoidCallback? onAudio;

  @override
  State<_ScoreMetadataDialog> createState() => _ScoreMetadataDialogState();
}

class _ScoreMetadataDialogState extends State<_ScoreMetadataDialog> {
  late final _title = TextEditingController(text: widget.score.title);
  late final _fields = {
    for (final key in scoreMetadataFields.keys)
      key: TextEditingController(text: widget.score.metadata[key] ?? ''),
  };
  bool _loading = false;
  String? _status;
  var _section = _MetadataSection.properties;
  late final _setlists = {
    for (final list in widget.setlists)
      if (list.scores.contains(widget.score.id)) list.id,
  };
  late final _libraries = widget.score.collections.toSet();
  late var _preview = widget.preview?.call(widget.score.page);

  void _loadPreview(int page) => setState(() {
    _preview = widget.preview?.call(page);
  });

  void _save({int? openPage}) => Navigator.pop<ScoreMetadataEdit>(context, (
    title: _title.text.trim(),
    fields: {
      for (final field in _fields.entries) field.key: field.value.text.trim(),
    },
    setlists: _setlists,
    libraries: _libraries,
    openPage: openPage,
  ));

  Widget _pagePreview() => FutureBuilder<ScorePreviewPage?>(
    future: _preview,
    builder: (_, snapshot) {
      final result = snapshot.data;
      final ready = snapshot.connectionState == ConnectionState.done;
      return Row(
        children: [
          SizedBox(
            width: 86,
            height: 112,
            child: switch (result?.image) {
              final bytes? => Image.memory(
                bytes,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
              null => const Icon(Icons.description_outlined),
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.score.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (result != null) ...[
                  Text('Page ${result.page} of ${result.total}'),
                  Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Previous preview page',
                        onPressed: ready && result.page > 1
                            ? () => _loadPreview(result.page - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next preview page',
                        onPressed: ready && result.page < result.total
                            ? () => _loadPreview(result.page + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed:
                        ready && !_loading && _title.text.trim().isNotEmpty
                        ? () => _save(openPage: result.page)
                        : null,
                    child: const Text('Save and open page'),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );

  Future<void> _usePdfInfo() async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final info = await widget.loadPdfInfo!();
      if (!mounted) return;
      setState(() {
        if (info['Title'] case final title?) _title.text = title;
        for (final (pdf, key) in [
          ('Author', 'composer'),
          ('Subject', 'reference'),
          ('Keywords', 'tags'),
        ]) {
          if (info[pdf] case final value?) _fields[key]!.text = value;
        }
        _status = info.isEmpty
            ? 'This PDF has no usable details.'
            : 'Review the imported details before saving.';
      });
    } catch (_) {
      if (mounted)
        setState(() => _status = 'Could not read the embedded PDF details.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;
    final sections = [
      for (final section in _MetadataSection.values)
        if ((section != _MetadataSection.midi || widget.onMidi != null) &&
            (section != _MetadataSection.audio || widget.onAudio != null))
          section,
    ];
    return AlertDialog(
      title: const Text('Score details'),
      content: SizedBox(
        width: wide ? 720 : 440,
        height: (size.height * .65).clamp(180.0, 620.0),
        child: wide
            ? Row(
                children: [
                  SizedBox(
                    width: 164,
                    child: ListView(
                      children: [
                        for (final section in sections)
                          ListTile(
                            leading: Icon(section.icon),
                            title: Text(section.label),
                            selected: section == _section,
                            onTap: () => setState(() => _section = section),
                          ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 20),
                  Expanded(child: _sectionContent()),
                ],
              )
            : Column(
                children: [
                  DropdownButton<_MetadataSection>(
                    isExpanded: true,
                    value: _section,
                    items: [
                      for (final section in sections)
                        DropdownMenuItem(
                          value: section,
                          child: Text(section.label),
                        ),
                    ],
                    onChanged: (section) {
                      if (section != null) setState(() => _section = section);
                    },
                  ),
                  Expanded(child: _sectionContent()),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading || _title.text.trim().isEmpty ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _membership({
    required Iterable<({String id, String name})> options,
    required Set<String> selected,
    required String empty,
  }) => ListView(
    children: [
      if (options.isEmpty) Text(empty),
      for (final option in options)
        CheckboxListTile(
          title: Text(option.name),
          value: selected.contains(option.id),
          onChanged: (value) => setState(() {
            if (value == true) {
              selected.add(option.id);
            } else {
              selected.remove(option.id);
            }
          }),
        ),
    ],
  );

  Widget _sectionContent() => switch (_section) {
    _MetadataSection.audio => ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.headphones_outlined),
          title: const Text('Linked audio'),
          subtitle: const Text('Link, replace, or remove this score’s track.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onAudio,
        ),
      ],
    ),
    _MetadataSection.midi => ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.settings_input_component),
          title: const Text('MIDI automation'),
          subtitle: const Text(
            'Configure open triggers, commands to send, and presets.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onMidi,
        ),
      ],
    ),
    _MetadataSection.setlists => _membership(
      options: widget.setlists.map((list) => (id: list.id, name: list.name)),
      selected: _setlists,
      empty: 'Create a setlist to add this score to it.',
    ),
    _MetadataSection.libraries => _membership(
      options: widget.libraries.map((name) => (id: name, name: name)),
      selected: _libraries,
      empty: 'Create a library to assign this score to it.',
    ),
    _MetadataSection.properties => ListView(
      key: const PageStorageKey('score-properties'),
      children: [
        if (_preview != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _pagePreview(),
          ),
        if (widget.loadPdfInfo != null)
          TextButton(
            onPressed: _loading ? null : _usePdfInfo,
            child: const Text('Use embedded PDF details'),
          ),
        if (_loading) const LinearProgressIndicator(),
        if (_status case final status?) Text(status),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
          onChanged: (_) => setState(() {}),
        ),
        for (final field in scoreMetadataFields.entries)
          TextField(
            controller: _fields[field.key],
            decoration: InputDecoration(
              labelText: field.value,
              hintText: field.key == 'duration'
                  ? 'm:ss, h:mm:ss, or whole minutes'
                  : null,
            ),
          ),
      ],
    ),
  };
}

Future<({Set<String> ids, String field, String value, bool append})?>
editBatchMetadata(
  BuildContext context,
  List<ScoreEntry> scores, {
  bool selectAll = false,
}) async {
  final ids = <String>{
    if (selectAll)
      for (final score in scores) score.id,
  };
  var field = 'tags';
  var append = true;
  var value = '';
  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Edit multiple scores'),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              DropdownButton<String>(
                isExpanded: true,
                value: field,
                items: [
                  for (final entry in scoreMetadataFields.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (next) => update(() {
                  field = next!;
                  append = {
                    'composer',
                    'genre',
                    'label',
                    'tags',
                  }.contains(field);
                }),
              ),
              if ({'composer', 'genre', 'label', 'tags'}.contains(field))
                SwitchListTile(
                  title: const Text('Append values'),
                  value: append,
                  onChanged: (next) => update(() => append = next),
                ),
              TextField(
                decoration: InputDecoration(
                  labelText: scoreMetadataFields[field],
                ),
                onChanged: (text) => update(() => value = text.trim()),
              ),
              for (final score in scores)
                CheckboxListTile(
                  title: Text(score.title),
                  value: ids.contains(score.id),
                  onChanged: (selected) => update(() {
                    if (selected == true) {
                      ids.add(score.id);
                    } else {
                      ids.remove(score.id);
                    }
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: ids.isEmpty || (append && value.isEmpty)
                ? null
                : () {
                    Navigator.pop(context, (
                      ids: ids,
                      field: field,
                      value: value,
                      append: append,
                    ));
                  },
            child: const Text('Apply'),
          ),
        ],
      ),
    ),
  );
}
