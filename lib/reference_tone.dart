import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'pitch_detection.dart';
import 'rehearsal_wave.dart';

class ReferenceTone {
  final _player = AudioPlayer();
  File? _file;

  Future<void> play(
    int midi, {
    bool sustained = false,
    ReferenceTimbre timbre = ReferenceTimbre.pure,
  }) async {
    await stop();
    final temp = await getTemporaryDirectory();
    final wave = File(
      '${temp.path}/encore-tone-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    _file = wave;
    try {
      await wave.writeAsBytes(
        referenceToneWave(
          noteFrequency(midi),
          sustained: sustained,
          timbre: timbre,
        ),
      );
      await _player.setFilePath(wave.path);
      await _player.setLoopMode(sustained ? LoopMode.one : LoopMode.off);
      unawaited(_player.play().catchError((Object _) {}));
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    await _player.stop();
    final old = _file;
    _file = null;
    if (old != null && await old.exists()) await old.delete();
  }

  Future<void> dispose() async {
    try {
      await stop();
    } finally {
      await _player.dispose();
    }
  }
}
