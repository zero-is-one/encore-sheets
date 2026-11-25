import 'package:material_ui/material_ui.dart';

import 'score_action.dart';

typedef MidiAutomation = ({String trigger, String commands});

String midiCommandKey(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');

class MidiAutomationDialog extends StatefulWidget {
  const MidiAutomationDialog({
    super.key,
    required this.initial,
    required this.presets,
    required this.savePresets,
  });

  final MidiAutomation initial;
  final Map<String, String> presets;
  final Future<void> Function(Map<String, String>) savePresets;

  @override
  State<MidiAutomationDialog> createState() => _MidiAutomationDialogState();
}

class _MidiAutomationDialogState extends State<MidiAutomationDialog> {
  late final _trigger = TextEditingController(text: widget.initial.trigger);
  late final _commands = TextEditingController(text: widget.initial.commands);
  final _presetName = TextEditingController();
  late final _presets = Map.of(widget.presets);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _trigger.dispose();
    _commands.dispose();
    _presetName.dispose();
    super.dispose();
  }

  List<String> get _lines => _commands.text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  String? _validatedCommands() {
    final formatted = <String>[];
    for (final line in _lines) {
      final bytes = ScoreAction.midiBytes(line);
      if (bytes == null) {
        setState(() => _error = 'Enter one valid MIDI message per line.');
        return null;
      }
      formatted.add(midiCommandKey(bytes));
    }
    return formatted.join('\n');
  }

  void _apply() {
    final commands = _validatedCommands();
    if (commands == null) return;
    final trigger = _trigger.text.trim();
    final bytes = trigger.isEmpty ? null : ScoreAction.midiBytes(trigger);
    if (trigger.isNotEmpty && bytes == null) {
      setState(() => _error = 'Enter a valid incoming MIDI message.');
      return;
    }
    Navigator.pop(context, (
      trigger: bytes == null ? '' : midiCommandKey(bytes),
      commands: commands,
    ));
  }

  Future<void> _savePreset() async {
    final commands = _validatedCommands();
    final name = _presetName.text.trim();
    if (commands == null) return;
    if (name.isEmpty || commands.isEmpty) {
      setState(() => _error = 'Enter a preset name and outgoing commands.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final presets = {..._presets, name: commands};
      await widget.savePresets(presets);
      if (!mounted) return;
      _presets.addAll(presets);
      _presetName.clear();
    } catch (_) {
      _error = 'Could not save the MIDI preset.';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('MIDI score automation'),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _trigger,
            decoration: const InputDecoration(
              labelText: 'Incoming message to open this score',
              hintText: 'C0 05',
            ),
          ),
          TextField(
            controller: _commands,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Messages sent when this score opens',
              hintText: 'C0 05',
              helperText:
                  'Hex bytes separated by spaces. One message per line.',
            ),
          ),
          if (_presets.isNotEmpty)
            DropdownButton<String>(
              hint: const Text('Use saved preset'),
              items: [
                for (final name in _presets.keys)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: _saving
                  ? null
                  : (name) {
                      _commands.text = _presets[name]!;
                    },
            ),
          TextField(
            controller: _presetName,
            decoration: const InputDecoration(labelText: 'New preset name'),
            maxLength: 60,
          ),
          TextButton(
            onPressed: _saving ? null : _savePreset,
            child: const Text('Save outgoing messages as preset'),
          ),
          if (_error case final error?) Text(error),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _apply,
        child: const Text('Save'),
      ),
    ],
  );
}
