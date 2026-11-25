import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_input.dart';

class ReaderShortcutsDialog extends StatefulWidget {
  const ReaderShortcutsDialog({
    super.key,
    required this.initial,
    required this.midi,
  });
  final Map<String, ReaderShortcut> initial;
  final Stream<String>? midi;

  @override
  State<ReaderShortcutsDialog> createState() => _ReaderShortcutsDialogState();
}

class _ReaderShortcutsDialogState extends State<ReaderShortcutsDialog> {
  late final _bindings = Map.of(widget.initial);
  final _focus = FocusNode();
  StreamSubscription<String>? _midi;
  ReaderShortcut? _capture;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _midi = widget.midi?.listen(_assign, onError: (Object _) {});
  }

  @override
  void dispose() {
    unawaited(_midi?.cancel());
    _focus.dispose();
    super.dispose();
  }

  void _assign(String key) {
    final action = _capture;
    if (action == null || !mounted) return;
    final prior = _bindings[key];
    setState(() {
      _bindings[key] = action;
      _capture = null;
      _notice = prior == null || prior == action
          ? 'Assigned ${shortcutLabel(key)}.'
          : 'Moved ${shortcutLabel(key)} from ${prior.label.toLowerCase()}.';
    });
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: (_, event) {
      if (_capture == null) return KeyEventResult.ignored;
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          setState(() => _capture = null);
        } else {
          _assign(shortcutKey(event.logicalKey));
        }
      }
      return KeyEventResult.handled;
    },
    child: AlertDialog(
      title: const Text('Input shortcuts'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_notice case final notice?) Text(notice),
            if (_capture case final action?)
              Text(
                'Press a key, pedal, or connected MIDI control for ${action.label.toLowerCase()}.',
              ),
            for (final action in ReaderShortcut.values) ...[
              ListTile(
                title: Text(action.label),
                trailing: TextButton(
                  onPressed: () {
                    setState(() {
                      _capture = action;
                      _notice = null;
                    });
                    _focus.requestFocus();
                  },
                  child: const Text('Bind'),
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final entry in _bindings.entries)
                    if (entry.value == action)
                      InputChip(
                        label: Text(shortcutLabel(entry.key)),
                        onDeleted: () =>
                            setState(() => _bindings.remove(entry.key)),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _bindings),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
