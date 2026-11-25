import 'package:flutter/services.dart';

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
