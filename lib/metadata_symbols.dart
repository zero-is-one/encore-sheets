import 'package:material_ui/material_ui.dart';

const metadataSymbols = {
  'music': Icons.music_note,
  'person': Icons.person_outline,
  'piano': Icons.piano,
  'tag': Icons.sell_outlined,
  'folder': Icons.folder_outlined,
  'star': Icons.star_outline,
  'flag': Icons.flag_outlined,
  'event': Icons.event_outlined,
  'book': Icons.book_outlined,
  'list': Icons.queue_music,
};

const metadataCategories = {
  'composer': 'Composer',
  'genre': 'Genre',
  'label': 'Label',
  'tags': 'Tag',
};

const additionalMusicStamps = {
  'mp': 'Mezzo-piano',
  'ppp': 'Pianississimo',
  'fff': 'Fortississimo',
  'sfz': 'Sforzando',
  'fp': 'Forte-piano',
  'sim.': 'Simile',
  'ten.': 'Tenuto',
  'stacc.': 'Staccato',
  'tutti': 'Tutti',
  'solo': 'Solo',
  'rit.': 'Ritardando',
  'accel.': 'Accelerando',
  'a tempo': 'Return to tempo',
  'D.C.': 'Da capo',
  'D.S.': 'Dal segno',
  'Fine': 'Fine',
  '↓': 'Down bow cue',
  '↑': 'Up bow cue',
};

Map<String, String> readMetadataSymbols(Object? stored) => {
  if (stored is Map)
    for (final key in metadataCategories.keys)
      if (stored[key] case final String symbol
          when metadataSymbols.containsKey(symbol))
        key: symbol,
};

Future<Map<String, String>?> chooseMetadataSymbols(
  BuildContext context,
  Map<String, String> current,
) {
  final draft = Map.of(current);
  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: const Text('Metadata symbols'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final category in metadataCategories.entries)
              ListTile(
                title: Text(category.value),
                trailing: DropdownButton<String>(
                  value: draft[category.key] ?? '',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Default')),
                    for (final option in metadataSymbols.entries)
                      DropdownMenuItem(
                        value: option.key,
                        child: Row(
                          children: [
                            Icon(option.value),
                            const SizedBox(width: 8),
                            Text(option.key),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) => refresh(() {
                    if (value == null || value.isEmpty) {
                      draft.remove(category.key);
                    } else {
                      draft[category.key] = value;
                    }
                  }),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
