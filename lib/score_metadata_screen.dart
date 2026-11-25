import 'package:material_ui/material_ui.dart';

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

Future<({String title, Map<String, String> fields})?> editScoreMetadata(
  BuildContext context,
  ScoreEntry score, {
  Future<Map<String, String>> Function()? loadPdfInfo,
}) => showDialog(
  context: context,
  builder: (_) => _ScoreMetadataDialog(score: score, loadPdfInfo: loadPdfInfo),
);

class _ScoreMetadataDialog extends StatefulWidget {
  const _ScoreMetadataDialog({required this.score, this.loadPdfInfo});

  final ScoreEntry score;
  final Future<Map<String, String>> Function()? loadPdfInfo;

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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Score details'),
    content: SizedBox(
      width: 440,
      child: ListView(
        shrinkWrap: true,
        children: [
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
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _loading || _title.text.trim().isEmpty
            ? null
            : () {
                Navigator.pop(context, (
                  title: _title.text.trim(),
                  fields: {
                    for (final field in _fields.entries)
                      field.key: field.value.text.trim(),
                  },
                ));
              },
        child: const Text('Save'),
      ),
    ],
  );
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
