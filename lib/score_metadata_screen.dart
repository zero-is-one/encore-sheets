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
  ScoreEntry score,
) => showDialog(
  context: context,
  builder: (_) => _ScoreMetadataDialog(score: score),
);

class _ScoreMetadataDialog extends StatefulWidget {
  const _ScoreMetadataDialog({required this.score});

  final ScoreEntry score;

  @override
  State<_ScoreMetadataDialog> createState() => _ScoreMetadataDialogState();
}

class _ScoreMetadataDialogState extends State<_ScoreMetadataDialog> {
  late final _title = TextEditingController(text: widget.score.title);
  late final _fields = {
    for (final key in scoreMetadataFields.keys)
      key: TextEditingController(text: widget.score.metadata[key] ?? ''),
  };

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
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            onChanged: (_) => setState(() {}),
          ),
          for (final field in scoreMetadataFields.entries)
            TextField(
              controller: _fields[field.key],
              decoration: InputDecoration(labelText: field.value),
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
        onPressed: _title.text.trim().isEmpty
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
