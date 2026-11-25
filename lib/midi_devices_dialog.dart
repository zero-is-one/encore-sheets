import 'dart:async';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:material_ui/material_ui.dart';

class MidiDevicesDialog extends StatefulWidget {
  const MidiDevicesDialog({super.key, required this.midi});
  final MidiCommand midi;

  @override
  State<MidiDevicesDialog> createState() => _MidiDevicesDialogState();
}

class _MidiDevicesDialogState extends State<MidiDevicesDialog> {
  List<MidiDevice> _devices = [];
  StreamSubscription<MidiSetupChange>? _changes;
  Timer? _scanTimer;
  bool _scanning = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _changes = widget.midi.onMidiSetupChanged?.listen((_) {
      unawaited(_refresh().catchError((Object _) {}));
    });
    _run(_refresh);
  }

  Future<void> _refresh() async {
    final devices = await widget.midi.devices ?? [];
    if (mounted) setState(() => _devices = devices);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      _error = 'Could not use MIDI. Check Bluetooth permissions and device pairing mode.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    if (_scanning) {
      _stopScan();
      return;
    }
    await widget.midi.startBluetooth();
    await widget.midi.waitUntilBluetoothIsInitialized().timeout(
      const Duration(seconds: 12),
    );
    if (widget.midi.bluetoothState != BluetoothState.poweredOn) {
      _error = 'Turn on Bluetooth and allow EncoreSheets to access it.';
      return;
    }
    if (!mounted) return;
    await widget.midi.startScanningForBluetoothDevices();
    if (!mounted) {
      widget.midi.stopScanningForBluetoothDevices();
      return;
    }
    _scanning = true;
    _scanTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(_stopScan);
    });
    await _refresh();
  }

  void _stopScan() {
    _scanTimer?.cancel();
    if (_scanning) widget.midi.stopScanningForBluetoothDevices();
    _scanning = false;
  }

  @override
  void dispose() {
    _stopScan();
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Pedals and MIDI devices'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Put a Bluetooth MIDI controller in pairing mode, then scan. Pair keyboard-mode pedals in your device’s Bluetooth settings.',
            ),
            if (_error case final error?) Text(error),
            if (_busy || _scanning) const LinearProgressIndicator(),
            if (!_busy && _devices.isEmpty)
              const Text('No MIDI devices found.'),
            for (final device in _devices)
              ListTile(
                title: Text(device.name),
                subtitle: Text(
                  device.connected
                      ? 'Connected'
                      : device.type == MidiDeviceType.ble
                      ? 'Bluetooth MIDI'
                      : 'MIDI',
                ),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          if (device.connected) {
                            widget.midi.disconnectDevice(device);
                          } else {
                            await widget.midi.connectToDevice(device);
                          }
                          await _refresh();
                        }),
                  child: Text(device.connected ? 'Disconnect' : 'Connect'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _run(_scan),
          child: Text(_scanning ? 'Stop scan' : 'Scan for Bluetooth MIDI'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
