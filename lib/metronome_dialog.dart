import 'package:material_ui/material_ui.dart';

import 'rehearsal_metronome.dart';
import 'rehearsal_wave.dart';

class MetronomeDialog extends StatefulWidget {
  const MetronomeDialog({super.key, required this.metronome});
  final RehearsalMetronome metronome;

  @override
  State<MetronomeDialog> createState() => _MetronomeDialogState();
}

class _MetronomeDialogState extends State<MetronomeDialog> {
  final _clock = Stopwatch()..start();
  final _taps = <int>[];
  bool _busy = false;
  String? _error;

  void _tap() => setState(() {
    final now = _clock.elapsedMilliseconds;
    if (_taps.isNotEmpty && now - _taps.last > 2500) _taps.clear();
    _taps.add(now);
    if (_taps.length > 5) _taps.removeAt(0);
    if (_taps.length > 1 && _taps.last > _taps.first) {
      widget.metronome.bpm =
          (60000 * (_taps.length - 1) / (_taps.last - _taps.first))
              .round()
              .clamp(25, 280);
    }
  });

  Future<void> _toggle() async {
    final meter = widget.metronome;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (meter.running) {
        await meter.stop();
      } else {
        await meter.start();
      }
    } catch (_) {
      _error = 'Could not start the metronome.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meter = widget.metronome;
    final editable = !_busy && !meter.running;
    return AlertDialog(
      title: const Text('Metronome'),
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error case final error?) Text(error),
            Text('${meter.bpm} BPM'),
            Slider(
              value: meter.bpm.toDouble(),
              min: 25,
              max: 280,
              divisions: 255,
              onChanged: editable
                  ? (value) => setState(() => meter.bpm = value.round())
                  : null,
            ),
            TextButton(
              onPressed: editable ? _tap : null,
              child: const Text('Tap tempo'),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DropdownButton<int>(
                  value: meter.beats,
                  items: [
                    for (var i = 1; i <= 16; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: editable
                      ? (value) => setState(() => meter.beats = value!)
                      : null,
                ),
                const Text(' / '),
                DropdownButton<int>(
                  value: meter.unit,
                  items: [
                    for (final i in [2, 4, 8, 16])
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: editable
                      ? (value) => setState(() => meter.unit = value!)
                      : null,
                ),
              ],
            ),
            SwitchListTile(
              title: const Text('Audible beat'),
              value: meter.audible,
              onChanged: editable
                  ? (value) => setState(() => meter.audible = value)
                  : null,
            ),
            SwitchListTile(
              title: const Text('Visual beat'),
              value: meter.visual,
              onChanged: editable
                  ? (value) => setState(() => meter.visual = value)
                  : null,
            ),
            SwitchListTile(
              title: const Text('One-bar count-in'),
              value: meter.countIn,
              onChanged: editable
                  ? (value) => setState(() => meter.countIn = value)
                  : null,
            ),
            DropdownButton<RehearsalChannel>(
              value: meter.channel,
              items: [
                for (final channel in RehearsalChannel.values)
                  DropdownMenuItem(
                    value: channel,
                    child: Text(switch (channel) {
                      RehearsalChannel.both => 'Both audio channels',
                      RehearsalChannel.left => 'Left audio channel',
                      RehearsalChannel.right => 'Right audio channel',
                    }),
                  ),
              ],
              onChanged: editable
                  ? (value) => setState(() => meter.channel = value!)
                  : null,
            ),
            MetronomeBeat(metronome: meter),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Done'),
        ),
        FilledButton(
          onPressed: _busy || !meter.audible && !meter.visual ? null : _toggle,
          child: Text(meter.running ? 'Stop' : 'Start'),
        ),
      ],
    );
  }
}

class MetronomeBeat extends StatelessWidget {
  const MetronomeBeat({super.key, required this.metronome});
  final RehearsalMetronome metronome;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: metronome,
    builder: (_, _) {
      if (!metronome.running || !metronome.visual)
        return const SizedBox.shrink();
      final label = metronome.countingIn ? 'Count-in' : 'Beat';
      return Semantics(
        label: '$label ${metronome.beat + 1} of ${metronome.beats}',
        child: Text('$label ${metronome.beat + 1} / ${metronome.beats}'),
      );
    },
  );
}
