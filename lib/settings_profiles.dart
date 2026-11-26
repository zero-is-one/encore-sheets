import 'package:material_ui/material_ui.dart';

import 'drawing_settings.dart';
import 'reader_preferences.dart';

typedef SettingsProfile = ({ReaderPreferences reader, DrawingSettings drawing});

Map<String, SettingsProfile> readSettingsProfiles(Object? saved) => {
  if (saved is Map)
    for (final entry in saved.entries)
      if (entry.key case final String name when name.trim().isNotEmpty)
        if (entry.value case {
          'reader': final Map reader,
          'drawing': final Object? drawing,
        })
          name: (
            reader: ReaderPreferences.fromJson(
              Map<String, dynamic>.from(reader),
            ),
            drawing: DrawingSettings.fromJson(drawing),
          ),
};

Map<String, Object> writeSettingsProfiles(
  Map<String, SettingsProfile> profiles,
) => {
  for (final item in profiles.entries)
    item.key: {
      'reader': item.value.reader.toJson(),
      'drawing': item.value.drawing.toJson(),
    },
};

class SettingsProfilesDialog extends StatefulWidget {
  const SettingsProfilesDialog({
    super.key,
    required this.saved,
    required this.current,
    required this.save,
  });
  final Map<String, SettingsProfile> saved;
  final SettingsProfile current;
  final Future<void> Function(Map<String, SettingsProfile>) save;

  @override
  State<SettingsProfilesDialog> createState() => _SettingsProfilesDialogState();
}

class _SettingsProfilesDialogState extends State<SettingsProfilesDialog> {
  late Map<String, SettingsProfile> _profiles = Map.of(widget.saved);
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _update(Map<String, SettingsProfile> next) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(next);
      _profiles = next;
      if (mounted) _name.clear();
    } catch (_) {
      _error = 'Could not save profiles.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _capture() {
    final name = _name.text.trim();
    if (name.isEmpty || _profiles.containsKey(name)) {
      setState(() => _error = 'Enter a new profile name.');
      return;
    }
    _update({..._profiles, name: widget.current});
  }

  Future<void> _remove(String name) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (mounted && remove == true)
      await _update(Map.of(_profiles)..remove(name));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Settings profiles'),
    scrollable: true,
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in _profiles.entries)
            ListTile(
              title: Text(item.key),
              subtitle: const Text('Tap to apply'),
              onTap: _busy ? null : () => Navigator.pop(context, item.value),
              trailing: IconButton(
                tooltip: 'Delete profile',
                onPressed: _busy ? null : () => _remove(item.key),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'New profile name'),
            maxLength: 60,
            enabled: !_busy,
            onSubmitted: (_) => _capture(),
          ),
          TextButton(
            onPressed: _busy ? null : _capture,
            child: const Text('Save current settings'),
          ),
          if (_error case final text?) Text(text),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
