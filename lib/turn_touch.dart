import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

String? turnTouchShortcut(List<int> data) {
  if (data.length != 2) return null;
  final button = switch ((data[0], data[1])) {
    (0xfe, 0) => 'North',
    (0xfd, 0) => 'East',
    (0xfb, 0) => 'West',
    (0xf7, 0) => 'South',
    (0xef, 0) => 'North double tap',
    (0xdf, 0) => 'East double tap',
    (0xbf, 0) => 'West double tap',
    (0x7f, 0) => 'South double tap',
    (0xfe, 0xff) => 'North hold',
    (0xfd, 0xff) => 'East hold',
    (0xfb, 0xff) => 'West hold',
    (0xf7, 0xff) => 'South hold',
    _ => null,
  };
  return button == null ? null : 'turntouch:$button';
}

class TurnTouch {
  TurnTouch(this.onPress);

  static const service = '99c31523-dc4f-41b1-bb04-4e4deb81fadd';
  static const _characteristic = '99c31525-dc4f-41b1-bb04-4e4deb81fadd';
  final void Function(String) onPress;
  final _connected = StreamController<bool>.broadcast();
  StreamSubscription<Uint8List>? _notifications;
  StreamSubscription<bool>? _connection;
  BleDevice? device;

  Stream<bool> get connectionChanges => _connected.stream;

  Future<void> connect(BleDevice remote) async {
    await disconnect();
    final id = remote.deviceId;
    await UniversalBle.connect(id, timeout: const Duration(seconds: 15));
    device = remote;
    try {
      _connection = UniversalBle.connectionStream(id).listen((connected) {
        if (!connected) unawaited(_clear());
      });
      _notifications =
          UniversalBle.characteristicValueStream(id, _characteristic).listen((
            data,
          ) {
            final key = turnTouchShortcut(data);
            if (key != null) onPress(key);
          });
      await UniversalBle.discoverServices(id);
      await UniversalBle.subscribeNotifications(id, service, _characteristic);
      if (device == null) throw StateError('The remote disconnected.');
      _connected.add(true);
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  Future<void> _clear() async {
    final hadDevice = device != null;
    device = null;
    final connection = _connection;
    final notifications = _notifications;
    _connection = null;
    _notifications = null;
    if (hadDevice) _connected.add(false);
    await connection?.cancel();
    await notifications?.cancel();
  }

  Future<void> disconnect() async {
    final id = device?.deviceId;
    await _clear();
    if (id != null) await UniversalBle.disconnect(id);
  }

  Future<void> dispose() async {
    try {
      await disconnect();
    } finally {
      await _connected.close();
    }
  }
}
