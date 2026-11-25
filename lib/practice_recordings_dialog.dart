import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'practice_recordings.dart';
import 'score_audio.dart';

class PracticeRecordingsDialog extends StatefulWidget {
  const PracticeRecordingsDialog({
    super.key,
    required this.takes,
    required this.audio,
  });
  final PracticeRecordings takes;
  final ScoreAudioSession audio;

  @override
  State<PracticeRecordingsDialog> createState() =>
      _PracticeRecordingsDialogState();
}

class _PracticeRecordingsDialogState extends State<PracticeRecordingsDialog> {
  List<String> _linked = [], _unlinked = [];
  bool _recording = false, _busy = false;
  String? _status;
  String? _playing;

  @override
  void initState() {
    super.initState();
    _run(_refresh);
  }

  Future<void> _refresh() async {
    _linked = await widget.takes.list();
    _unlinked = await widget.takes.unlinked();
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await task();
    } catch (_) {
      _status = 'Could not complete the recording action.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(widget.takes.dispose().catchError((Object _) {}));
    super.dispose();
  }

  Widget _row(String file, bool unlinked) {
    final stamp = int.parse(file.substring(9, file.length - 4));
    final time = DateTime.fromMicrosecondsSinceEpoch(stamp);
    final date = MaterialLocalizations.of(context).formatShortDate(time);
    final hour = TimeOfDay.fromDateTime(time).format(context);
    return ListTile(
      title: Text('$date · $hour'),
      leading: IconButton(
        tooltip: _playing == file ? 'Stop take' : 'Play take',
        icon: Icon(_playing == file ? Icons.stop : Icons.play_arrow),
        onPressed: _busy || _recording
            ? null
            : () => _run(() async {
                if (_playing == file) {
                  await widget.audio.stop();
                  _playing = null;
                } else {
                  await widget.audio.playTake(await widget.takes.path(file));
                  _playing = file;
                }
              }),
      ),
      trailing: PopupMenuButton<String>(
        enabled: !_busy && !_recording,
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'share', child: Text('Share')),
          if (!unlinked)
            const PopupMenuItem(
              value: 'unlink',
              child: Text('Unlink from score'),
            ),
          const PopupMenuItem(value: 'delete', child: Text('Delete recording')),
        ],
        onSelected: (action) => _run(() async {
          if (action == 'share') {
            final box = context.findRenderObject() as RenderBox;
            final origin = box.localToGlobal(Offset.zero) & box.size;
            final path = await widget.takes.path(file);
            await SharePlus.instance.share(
              ShareParams(
                files: [XFile(path, mimeType: 'audio/mp4')],
                sharePositionOrigin: origin,
              ),
            );
            return;
          }
          if (action == 'delete') {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialog) => AlertDialog(
                title: const Text('Delete this recording?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
          }
          if (_playing == file) {
            await widget.audio.stop();
            _playing = null;
          }
          await widget.takes.remove(
            file,
            delete: action == 'delete',
            unlinked: unlinked,
          );
          await _refresh();
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_recording && !_busy,
    child: AlertDialog(
      title: const Text('Practice recordings'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_status case final status?) Text(status),
            if (_busy) const LinearProgressIndicator(),
            if (_recording) const Text('Recording…'),
            if (!_recording && _linked.isEmpty)
              const Text('No takes linked to this score.'),
            for (final file in _linked.reversed) _row(file, false),
            if (_unlinked.isNotEmpty) const Text('Unlinked takes'),
            for (final file in _unlinked.reversed) _row(file, true),
          ],
        ),
      ),
      actions: _recording
          ? [
              TextButton(
                onPressed: _busy ? null : () => _finish(false),
                child: const Text('Discard'),
              ),
              FilledButton(
                onPressed: _busy ? null : () => _finish(true),
                child: const Text('Save take'),
              ),
            ]
          : [
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Done'),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await widget.audio.stop();
                        _playing = null;
                        _recording = await widget.takes.start();
                        if (!_recording)
                          _status =
                              'Microphone access is required to record a take.';
                      }),
                child: const Text('Record'),
              ),
            ],
    ),
  );

  Future<void> _finish(bool save) => _run(() async {
    await widget.takes.finish(save: save);
    _recording = false;
    await _refresh();
  });
}
