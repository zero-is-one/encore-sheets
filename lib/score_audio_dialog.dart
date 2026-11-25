import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';

import 'program_duration.dart';
import 'score_audio.dart';

class ScoreAudioDialog extends StatefulWidget {
  const ScoreAudioDialog({
    super.key,
    required this.audio,
    required this.selection,
    required this.title,
  });

  final ScoreAudioSession audio;
  final String selection;
  final String title;

  @override
  State<ScoreAudioDialog> createState() => _ScoreAudioDialogState();
}

class _ScoreAudioDialogState extends State<ScoreAudioDialog> {
  bool _busy = false;
  String? _track;
  String? _error;
  late double _speed = widget.audio.player.speed;
  late double _pitch = 12 * math.log(widget.audio.player.pitch) / math.ln2;
  String get _selection => widget.audio.pinnedSelection ?? widget.selection;

  @override
  void initState() {
    super.initState();
    _run(_loadTrack);
  }

  Future<void> _loadTrack() async {
    _track = (await widget.audio.track(_selection))?.name;
    await widget.audio.open(_selection);
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Could not load or change the audio track.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach() => _run(() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Audio files',
          extensions: [
            'mp3',
            'm4a',
            'aac',
            'wav',
            'flac',
            'ogg',
            'aif',
            'aiff',
          ],
          mimeTypes: ['audio/*'],
          uniformTypeIdentifiers: ['public.audio'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    await widget.audio.attach(_selection, file);
    _track = file.name;
  });

  @override
  Widget build(BuildContext context) {
    final player = widget.audio.player;
    return AlertDialog(
      title: Text(
        widget.audio.pinnedSelection != null && _selection != widget.selection
            ? 'Pinned audio'
            : 'Audio · ${widget.title}',
      ),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_track ?? 'No linked audio'),
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?) Text(error),
            if (_track != null) ...[
              StreamBuilder<Duration?>(
                stream: player.durationStream,
                initialData: player.duration,
                builder: (_, duration) => StreamBuilder<Duration>(
                  stream: player.positionStream,
                  initialData: player.position,
                  builder: (_, position) {
                    final total = duration.data ?? Duration.zero;
                    final elapsed = position.data ?? Duration.zero;
                    return Column(
                      children: [
                        Slider(
                          value: elapsed.inMilliseconds.toDouble().clamp(
                            0.0,
                            total.inMilliseconds.toDouble(),
                          ),
                          max: total.inMilliseconds > 0
                              ? total.inMilliseconds.toDouble()
                              : 1,
                          onChanged: _busy || total == Duration.zero
                              ? null
                              : (value) {
                                  player.seek(
                                    Duration(milliseconds: value.round()),
                                  );
                                },
                        ),
                        Text(
                          '${formatProgramDuration(elapsed)} / ${formatProgramDuration(total)}',
                        ),
                      ],
                    );
                  },
                ),
              ),
              StreamBuilder<PlayerState>(
                stream: player.playerStateStream,
                initialData: player.playerState,
                builder: (_, state) {
                  final playing =
                      state.data?.playing == true &&
                      state.data?.processingState != ProcessingState.completed;
                  return TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await widget.audio.toggle(_selection);
                          }),
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    label: Text(playing ? 'Pause' : 'Play'),
                  );
                },
              ),
              Text('Speed · ${_speed.toStringAsFixed(2)}×'),
              Slider(
                value: _speed.clamp(.5, 2.0),
                min: .5,
                max: 2,
                divisions: 30,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _speed = value),
                onChangeEnd: (value) => _run(() => player.setSpeed(value)),
              ),
              if (ScoreAudioSession.supportsPitch) ...[
                Text('Pitch · ${_pitch.round()} semitones'),
                Slider(
                  value: _pitch.clamp(-12.0, 12.0),
                  min: -12,
                  max: 12,
                  divisions: 24,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _pitch = value),
                  onChangeEnd: (value) => _run(
                    () => player.setPitch(math.pow(2, value / 12).toDouble()),
                  ),
                ),
              ],
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy || widget.audio.looping
                        ? null
                        : () => setState(widget.audio.markLoopStart),
                    child: const Text('Set A'),
                  ),
                  TextButton(
                    onPressed:
                        _busy ||
                            widget.audio.loopStart == null ||
                            widget.audio.looping
                        ? null
                        : () => _run(widget.audio.markLoopEnd),
                    child: const Text('Set B & loop'),
                  ),
                  TextButton(
                    onPressed: _busy || widget.audio.loopStart == null
                        ? null
                        : () => _run(widget.audio.clearLoop),
                    child: const Text('Clear loop'),
                  ),
                ],
              ),
              if (widget.audio.loopStart case final start?)
                Text(
                  'A ${formatProgramDuration(start)}'
                  '${widget.audio.loopEnd == null ? '' : ' · B ${formatProgramDuration(widget.audio.loopEnd!)}'}',
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep playing across scores'),
                value: widget.audio.pinnedSelection != null,
                onChanged: _busy
                    ? null
                    : (enabled) => _run(() async {
                        final previous = _selection;
                        widget.audio.pinnedSelection = enabled
                            ? widget.selection
                            : null;
                        if (previous != _selection) {
                          await widget.audio.stop();
                          await _loadTrack();
                        }
                      }),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _attach,
          child: Text(
            _track == null ? 'Link audio file' : 'Replace audio file',
          ),
        ),
        if (_track != null)
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await widget.audio.unlink(_selection);
                    await _loadTrack();
                  }),
            child: const Text('Unlink'),
          ),
        FilledButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
