import 'package:material_ui/material_ui.dart';

import 'rehearsal_metronome.dart';
import 'rehearsal_wave.dart';

class MetronomeDialog extends StatefulWidget {
  const MetronomeDialog({
    super.key,
    required this.metronome,
    this.page,
    this.initialPageBeats = 0,
    this.onPageBeatsChanged,
  });
  final RehearsalMetronome metronome;
  final int? page;
  final int initialPageBeats;
  final ValueChanged<int>? onPageBeatsChanged;

  @override
  State<MetronomeDialog> createState() => _MetronomeDialogState();
}

class _MetronomeDialogState extends State<MetronomeDialog> {
  final _clock = Stopwatch()..start();
  final _taps = <int>[];
  late final _pageBeats = TextEditingController(
    text: widget.initialPageBeats == 0 ? '' : '${widget.initialPageBeats}',
  );
  bool _busy = false;
  bool _measures = false;
  String? _error;

  @override
  void dispose() {
    _pageBeats.dispose();
    super.dispose();
  }

  void _savePageBeats(String value) {
    final count = int.tryParse(value.trim());
    if (value.trim().isEmpty) {
      widget.onPageBeatsChanged?.call(0);
    } else if (count != null && count >= 0 && count <= _maximumCount) {
      widget.onPageBeatsChanged?.call(
        _measures ? count * widget.metronome.beats : count,
      );
    }
  }

  int get _maximumCount => _measures ? 4096 ~/ widget.metronome.beats : 4096;

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
    final count = int.tryParse(_pageBeats.text.trim());
    final invalidCount =
        _pageBeats.text.trim().isNotEmpty &&
        (count == null || count < 0 || count > _maximumCount);
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
                      ? (value) => setState(() {
                          meter.beats = value!;
                          _savePageBeats(_pageBeats.text);
                        })
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
            if (widget.page case final page?) ...[
              const Divider(),
              TextField(
                controller: _pageBeats,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText:
                      '${_measures ? 'Measures' : 'Beats'} before turning page $page',
                  helperText: 'Leave blank for manual turns',
                  errorText: invalidCount
                      ? 'Enter a whole number from 0 to $_maximumCount'
                      : null,
                ),
                onChanged: (value) => setState(() => _savePageBeats(value)),
              ),
              DropdownButton<bool>(
                value: _measures,
                items: const [
                  DropdownMenuItem(value: false, child: Text('Beats')),
                  DropdownMenuItem(value: true, child: Text('Measures')),
                ],
                onChanged: (value) => setState(() {
                  final count = int.tryParse(_pageBeats.text.trim());
                  _measures = value!;
                  if (count != null && count >= 0) {
                    final converted = _measures
                        ? (count / meter.beats).ceil()
                        : count * meter.beats;
                    _pageBeats.text = '${converted.clamp(0, _maximumCount)}';
                    _savePageBeats(_pageBeats.text);
                  }
                }),
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
