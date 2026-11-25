import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'rehearsal_wave.dart';

class RehearsalMetronome extends ChangeNotifier {
  final _player = AudioPlayer();
  Timer? _timer;
  File? _wave;
  int bpm = 96, beats = 4, unit = 4, beat = 0;
  bool audible = true, visual = true, countIn = false, countingIn = false;
  bool running = false;
  RehearsalChannel channel = RehearsalChannel.both;

  Future<void> start() async {
    if (running) return;
    final temp = await getTemporaryDirectory();
    final wave = File(
      '${temp.path}/encore-click-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    _wave = wave;
    try {
      await wave.writeAsBytes(metronomeWave(bpm, beats, channel));
      await _player.setFilePath(wave.path);
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(audible ? 1 : 0);
      beat = 0;
      countingIn = countIn;
      running = true;
      var lastPosition = Duration.zero;
      _timer = Timer.periodic(const Duration(milliseconds: 22), (_) {
        final position = _player.position;
        final current = (position.inMicroseconds * bpm ~/ 60000000).clamp(
          0,
          beats - 1,
        );
        final wrapped = position < lastPosition;
        lastPosition = position;
        if (current == beat && !(wrapped && countingIn)) return;
        if (wrapped) countingIn = false;
        beat = current;
        notifyListeners();
      });
      unawaited(_player.play().catchError((Object _) {}));
      notifyListeners();
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    running = countingIn = false;
    await _player.stop();
    final wave = _wave;
    _wave = null;
    if (wave != null && await wave.exists()) await wave.delete();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    final wave = _wave;
    unawaited(
      _player
          .dispose()
          .whenComplete(() async {
            if (wave != null && await wave.exists()) await wave.delete();
          })
          .catchError((Object _) {}),
    );
    super.dispose();
  }
}
