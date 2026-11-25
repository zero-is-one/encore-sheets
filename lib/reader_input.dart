import 'package:flutter/services.dart';

enum ReaderShortcut {
  next('Next page'),
  previous('Previous page'),
  controls('Toggle controls'),
  markup('Toggle markup'),
  audio('Play or pause audio');

  const ReaderShortcut(this.label);
  final String label;
}

String shortcutKey(LogicalKeyboardKey key) => 'key:${key.keyId}';

String? shortcutMidi(List<int> bytes) {
  if (bytes.length < 3) return null;
  final kind = bytes[0] & 0xf0;
  if (kind == 0x90 && bytes[2] > 0) return 'midi:${bytes[0]}:${bytes[1]}';
  if (kind == 0xb0 && bytes[2] > 0) return 'midi:${bytes[0]}:${bytes[1]}';
  return null;
}

String shortcutLabel(String code) {
  final parts = code.split(':');
  if (parts.length == 2 && parts.first == 'key') {
    final id = int.tryParse(parts[1]);
    return id == null ? code : LogicalKeyboardKey(id).keyLabel;
  }
  if (parts.length == 3 && parts.first == 'midi') {
    final status = int.tryParse(parts[1]);
    if (status == null) return code;
    return 'MIDI ch ${(status & 15) + 1} · ${status & 0xf0 == 0x90 ? 'note' : 'CC'} ${parts[2]}';
  }
  return code;
}

int pageTurnForKey(LogicalKeyboardKey key, {bool reverse = false}) {
  final step = switch (key) {
    LogicalKeyboardKey.arrowRight ||
    LogicalKeyboardKey.arrowDown ||
    LogicalKeyboardKey.pageDown ||
    LogicalKeyboardKey.space ||
    LogicalKeyboardKey.enter ||
    LogicalKeyboardKey.numpadEnter => 1,
    LogicalKeyboardKey.arrowLeft ||
    LogicalKeyboardKey.arrowUp ||
    LogicalKeyboardKey.pageUp => -1,
    _ => 0,
  };
  return reverse ? -step : step;
}
