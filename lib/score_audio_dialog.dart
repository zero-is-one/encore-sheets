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

  @override
  void initState() {
    super.initState();
    _run(() async {
      _track = (await widget.audio.track(widget.selection))?.name;
      await widget.audio.open(widget.selection);
    });
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not load or change the audio track.');
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
    await widget.audio.attach(widget.selection, file);
    _track = file.name;
  });

  @override
  Widget build(BuildContext context) {
    final player = widget.audio.player;
    return AlertDialog(
      title: Text('Audio · ${widget.title}'),
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
                            await widget.audio.toggle(widget.selection);
                          }),
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    label: Text(playing ? 'Pause' : 'Play'),
                  );
                },
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
                    await widget.audio.unlink(widget.selection);
                    _track = null;
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
