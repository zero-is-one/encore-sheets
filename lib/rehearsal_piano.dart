import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'rehearsal_wave.dart';

class RehearsalPiano {
  final _notes = <int, Future<File>>{};
  final _playing = <int, AudioPlayer>{};
  final _tasks = <Future<void>>{};
  late final _folder = getTemporaryDirectory().then(
    (root) => root.createTemp('encore-keys-'),
  );
  bool _prepared = false, _closed = false;

  Future<File> _sample(int note) => _notes.putIfAbsent(note, () async {
    _prepared = true;
    final folder = await _folder;
    final bytes = await Isolate.run(() => pianoNoteWave(note));
    return File('${folder.path}/$note.wav').writeAsBytes(bytes);
  });

  Future<void> play(int note, {int velocity = 100}) {
    if (_closed || _tasks.length >= 8 || note < 0 || note > 127) {
      return Future.value();
    }
    final task = _play(note, velocity);
    _tasks.add(task);
    return task.whenComplete(() => _tasks.remove(task));
  }

  Future<void> _play(int note, int velocity) async {
    AudioPlayer? voice;
    try {
      final sample = await _sample(note);
      if (_closed) return;
      final previous = _playing[note];
      if (previous != null) await previous.stop();
      if (_closed) return;
      final player = voice = AudioPlayer();
      _playing[note] = player;
      await player.setFilePath(sample.path);
      await player.setVolume((velocity / 127).clamp(0.0, 1.0));
      if (!_closed) await player.play();
    } catch (_) {
      _notes.remove(note);
      rethrow;
    } finally {
      if (_playing[note] == voice) _playing.remove(note);
      await voice?.dispose();
    }
  }

  Future<void> dispose() async {
    _closed = true;
    await Future.wait([
      for (final voice in _playing.values.toList())
        voice.stop().catchError((Object _) {}),
      for (final task in _tasks.toList()) task.catchError((Object _) {}),
    ]);
    if (_prepared) {
      try {
        await (await _folder).delete(recursive: true);
      } on FileSystemException {
        // The OS can remove temporary audio independently.
      }
    }
  }
}

class RehearsalPianoDialog extends StatefulWidget {
  const RehearsalPianoDialog({
    super.key,
    required this.piano,
    required this.midiSound,
    required this.onMidiSound,
  });
  final RehearsalPiano piano;
  final bool midiSound;
  final ValueChanged<bool> onMidiSound;

  @override
  State<RehearsalPianoDialog> createState() => _RehearsalPianoDialogState();
}

class _RehearsalPianoDialogState extends State<RehearsalPianoDialog> {
  late bool _midiSound = widget.midiSound;
  int _octave = 4;
  String? _error;

  Future<void> _play(int offset) async {
    try {
      await widget.piano.play((_octave + 1) * 12 + offset);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not play this note.');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Piano'),
    scrollable: true,
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Lower octave',
                onPressed: _octave <= 1
                    ? null
                    : () => setState(() => _octave--),
                icon: const Icon(Icons.remove),
              ),
              Text('Octave $_octave'),
              IconButton(
                tooltip: 'Higher octave',
                onPressed: _octave >= 7
                    ? null
                    : () => setState(() => _octave++),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          SizedBox(
            height: 150,
            child: LayoutBuilder(
              builder: (context, space) {
                const whiteNotes = [0, 2, 4, 5, 7, 9, 11];
                const blackNotes = {1: 1, 2: 3, 4: 6, 5: 8, 6: 10};
                const labels = [
                  'C',
                  'C♯',
                  'D',
                  'D♯',
                  'E',
                  'F',
                  'F♯',
                  'G',
                  'G♯',
                  'A',
                  'A♯',
                  'B',
                ];
                final width = space.maxWidth / whiteNotes.length;
                Widget key(int note, bool black) => Semantics(
                  button: true,
                  label: '${labels[note]} $_octave',
                  child: Material(
                    color: black ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Colors.black45),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: InkWell(
                      onTap: () => _play(note),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            labels[note],
                            style: TextStyle(
                              color: black ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                return Stack(
                  children: [
                    Row(
                      children: [
                        for (final note in whiteNotes)
                          Expanded(child: key(note, false)),
                      ],
                    ),
                    for (final entry in blackNotes.entries)
                      Positioned(
                        left: width * (entry.key - .32),
                        width: width * .64,
                        height: 92,
                        child: key(entry.value, true),
                      ),
                  ],
                );
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Play notes from connected MIDI controllers'),
            value: _midiSound,
            onChanged: (value) {
              setState(() => _midiSound = value);
              widget.onMidiSound(value);
            },
          ),
          if (_error case final error?) Text(error),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
