import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:record/record.dart';

import 'pitch_detection.dart';
import 'reference_tone.dart';
import 'rehearsal_wave.dart';

enum _TunerSensitivity {
  quiet('Quiet input', .000005),
  standard('Standard', .000015),
  loud('Reduce background pickup', .00006);

  const _TunerSensitivity(this.label, this.minimumEnergy);
  final String label;
  final double minimumEnergy;
}

class TunerDialog extends StatefulWidget {
  const TunerDialog({super.key, required this.tone, required this.microphone});
  final ReferenceTone tone;
  final bool microphone;

  @override
  State<TunerDialog> createState() => _TunerDialogState();
}

class _TunerDialogState extends State<TunerDialog> {
  static const _rate = 16000;
  static const _window = 8192;
  final _recorder = AudioRecorder();
  final _pcm = Uint8List(_window);
  StreamSubscription<Uint8List>? _stream;
  int _samples = 0;
  int _reference = 69;
  ReferenceTimbre _timbre = ReferenceTimbre.pure;
  _TunerSensitivity _sensitivity = _TunerSensitivity.standard;
  double? _frequency;
  bool _listening = false, _busy = false, _holding = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      _error = 'Could not use audio on this device.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _listen() async {
    if (_listening) {
      await _stop();
      return;
    }
    await widget.tone.stop();
    _holding = false;
    if (!await _recorder.hasPermission()) {
      _error = 'Microphone access is required for tuning.';
      return;
    }
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _rate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    if (!mounted) {
      await _recorder.stop();
      return;
    }
    _listening = true;
    _samples = 0;
    _stream = stream.listen(
      (chunk) {
        for (final byte in chunk) {
          _pcm[_samples++] = byte;
          if (_samples == _window) {
            _samples = 0;
            if (mounted)
              setState(
                () => _frequency = estimatePitch(
                  _pcm,
                  _rate,
                  minimumEnergy: _sensitivity.minimumEnergy,
                ),
              );
          }
        }
      },
      onError: (Object _) {
        if (mounted)
          setState(() => _error = 'Microphone input was interrupted.');
      },
    );
  }

  Future<void> _stop() async {
    await _stream?.cancel();
    _stream = null;
    if (_listening) await _recorder.stop();
    _listening = false;
    _frequency = null;
  }

  Future<void> _toggleHold() async {
    if (_holding) {
      await widget.tone.stop();
      _holding = false;
      return;
    }
    await _stop();
    await widget.tone.play(_reference, sustained: true, timbre: _timbre);
    _holding = true;
  }

  @override
  void dispose() {
    unawaited(
      _stop().whenComplete(_recorder.dispose).catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frequency = _frequency;
    final pitch = frequency == null ? null : describePitch(frequency);
    return AlertDialog(
      title: const Text('Pitch pipe & tuner'),
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error case final error?) Text(error),
            DropdownButton<int>(
              value: _reference,
              onChanged: _busy || _holding
                  ? null
                  : (value) => setState(() => _reference = value!),
              items: [
                for (var note = 48; note <= 84; note++)
                  DropdownMenuItem(value: note, child: Text(noteLabel(note))),
              ],
            ),
            Text('${noteFrequency(_reference).toStringAsFixed(1)} Hz'),
            DropdownButton<ReferenceTimbre>(
              value: _timbre,
              onChanged: _busy || _holding
                  ? null
                  : (value) => setState(() => _timbre = value!),
              items: [
                for (final timbre in ReferenceTimbre.values)
                  DropdownMenuItem(value: timbre, child: Text(timbre.label)),
              ],
            ),
            TextButton.icon(
              onPressed: _busy || _holding
                  ? null
                  : () => _run(() async {
                      await _stop();
                      await widget.tone.play(_reference, timbre: _timbre);
                    }),
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('Play reference tone'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => _run(_toggleHold),
              icon: Icon(_holding ? Icons.stop : Icons.repeat),
              label: Text(_holding ? 'Stop drone' : 'Hold note'),
            ),
            if (widget.microphone) ...[
              const Divider(),
              DropdownButtonFormField<_TunerSensitivity>(
                initialValue: _sensitivity,
                decoration: const InputDecoration(
                  labelText: 'Tuner sensitivity',
                ),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _sensitivity = value!),
                items: [
                  for (final sensitivity in _TunerSensitivity.values)
                    DropdownMenuItem(
                      value: sensitivity,
                      child: Text(sensitivity.label),
                    ),
                ],
              ),
              if (_listening)
                Text(
                  pitch == null
                      ? 'Listening for a steady note…'
                      : '${noteLabel(pitch.midi)} · ${frequency!.toStringAsFixed(1)} Hz · '
                            '${pitch.cents >= 0 ? '+' : ''}${pitch.cents.toStringAsFixed(0)} cents',
                ),
              if (pitch != null)
                Slider(
                  value: pitch.cents.clamp(-50.0, 50.0),
                  min: -50,
                  max: 50,
                  onChanged: null,
                ),
              TextButton.icon(
                onPressed: _busy ? null : () => _run(_listen),
                icon: Icon(_listening ? Icons.mic_off : Icons.mic_none),
                label: Text(_listening ? 'Stop tuner' : 'Use microphone'),
              ),
            ],
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
}
