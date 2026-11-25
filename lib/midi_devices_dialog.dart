import 'dart:async';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:material_ui/material_ui.dart';
import 'package:universal_ble/universal_ble.dart';

import 'turn_touch.dart';

class MidiDevicesDialog extends StatefulWidget {
  const MidiDevicesDialog({
    super.key,
    required this.midi,
    required this.turnTouch,
  });
  final MidiCommand midi;
  final TurnTouch turnTouch;

  @override
  State<MidiDevicesDialog> createState() => _MidiDevicesDialogState();
}

class _MidiDevicesDialogState extends State<MidiDevicesDialog> {
  List<MidiDevice> _devices = [];
  StreamSubscription<MidiSetupChange>? _changes;
  StreamSubscription<bool>? _remoteConnection;
  StreamSubscription<BleDevice>? _remoteScan;
  final _remotes = <String, BleDevice>{};
  Timer? _scanTimer;
  bool _scanning = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _changes = widget.midi.onMidiSetupChanged?.listen((_) {
      unawaited(_refresh().catchError((Object _) {}));
    });
    _remoteConnection = widget.turnTouch.connectionChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _run(_refresh);
  }

  Future<void> _refresh() async {
    final devices = await widget.midi.devices ?? [];
    if (mounted) setState(() => _devices = devices);
  }

  Future<void> _run(Future<void> Function() action, {String? device}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      _error =
          'Could not use ${device ?? 'MIDI'}. Check Bluetooth permissions and device pairing mode.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    await _stopRemoteScan();
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

  Future<void> _scanRemotes() async {
    if (_remoteScan != null) {
      await _stopRemoteScan();
      return;
    }
    _stopScan();
    await UniversalBle.requestPermissions();
    _remotes.clear();
    _remoteScan = UniversalBle.scanStream.listen((remote) {
      if (mounted) setState(() => _remotes[remote.deviceId] = remote);
    });
    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: [TurnTouch.service]),
      );
      _scanTimer = Timer(const Duration(seconds: 12), () {
        unawaited(_run(_stopRemoteScan, device: 'Turn Touch'));
      });
    } catch (_) {
      await _stopRemoteScan();
      rethrow;
    }
  }

  Future<void> _stopRemoteScan() async {
    final scan = _remoteScan;
    if (scan == null) return;
    _remoteScan = null;
    _scanTimer?.cancel();
    await scan.cancel();
    await UniversalBle.stopScan();
  }

  @override
  void dispose() {
    _stopScan();
    unawaited(_stopRemoteScan().catchError((Object _) {}));
    unawaited(_changes?.cancel());
    unawaited(_remoteConnection?.cancel());
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
              'Scan in MIDI mode for BlueBoard or Genki Wave. Pair AirTurn and other keyboard-mode pedals in your device’s Bluetooth settings.',
            ),
            if (_error case final error?) Text(error),
            if (_busy || _scanning || _remoteScan != null)
              const LinearProgressIndicator(),
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
            const Divider(),
            if (widget.turnTouch.device case final remote?)
              ListTile(
                title: Text(remote.name ?? 'Turn Touch Remote'),
                subtitle: const Text('Turn Touch connected'),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          widget.turnTouch.disconnect,
                          device: 'Turn Touch',
                        ),
                  child: const Text('Disconnect'),
                ),
              ),
            for (final remote in _remotes.values)
              if (remote.deviceId != widget.turnTouch.device?.deviceId)
                ListTile(
                  title: Text(remote.name ?? 'Turn Touch Remote'),
                  trailing: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _stopRemoteScan();
                            await widget.turnTouch.connect(remote);
                          }, device: 'Turn Touch'),
                    child: const Text('Connect'),
                  ),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(_scanRemotes, device: 'Turn Touch'),
          child: Text(
            _remoteScan == null
                ? 'Scan for Turn Touch'
                : 'Stop Turn Touch scan',
          ),
        ),
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
