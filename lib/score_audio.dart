import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'score_library.dart';

class ScoreAudioSession {
  ScoreAudioSession(this.library);
  final ScoreLibrary library;
  final player = AudioPlayer();
  String? _loaded;

  static bool get supported =>
      !kIsWeb &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  Future<String> _folder() async =>
      (await getApplicationDocumentsDirectory()).path;

  Future<Map<String, dynamic>> _attachments() async {
    final preferences = await library.storage.readPreferences();
    return (preferences['localScoreAudio'] as Map?)?.cast<String, dynamic>() ??
        {};
  }

  Future<({String file, String name})?> track(String selection) async {
    final data = (await _attachments())[selection];
    if (data case {'file': final String file, 'name': final String name}
        when RegExp(r'^score-audio-[0-9]+\.[a-z0-9]+$').hasMatch(file)) {
      return (file: file, name: name);
    }
    return null;
  }

  Future<void> attach(String selection, XFile source) async {
    final extension = source.name.split('.').last.toLowerCase();
    if (!RegExp(r'^[a-z0-9]{1,6}$').hasMatch(extension)) {
      throw const FormatException('Unsupported track filename');
    }
    final file =
        'score-audio-${DateTime.now().microsecondsSinceEpoch}.$extension';
    final folder = await _folder();
    final previous = await track(selection);
    final attachments = await _attachments();
    final path = '$folder/$file';
    try {
      await source.saveTo(path);
      await player.setFilePath(path);
      await library.updatePreferences({
        'localScoreAudio': {
          ...attachments,
          selection: {'file': file, 'name': source.name},
        },
      });
      _loaded = file;
    } catch (_) {
      await stop();
      await _discard(path);
      rethrow;
    }
    if (previous != null) await _discard('$folder/${previous.file}');
  }

  Future<void> unlink(String selection) async {
    final previous = await track(selection);
    final attachments = await _attachments();
    attachments.remove(selection);
    await library.updatePreferences({'localScoreAudio': attachments});
    await stop();
    if (previous != null) await _discard('${await _folder()}/${previous.file}');
  }

  Future<void> _discard(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Unreferenced media can no longer be opened by the reader.
    }
  }

  Future<bool> open(String selection) async {
    final found = await track(selection);
    if (found == null) return false;
    if (_loaded != found.file) {
      await player.setFilePath('${await _folder()}/${found.file}');
      _loaded = found.file;
    }
    return true;
  }

  Future<bool> toggle(String selection) async {
    if (!await open(selection)) return false;
    if (player.processingState == ProcessingState.completed) {
      await player.pause();
      await player.seek(Duration.zero);
    }
    if (player.playing) {
      await player.pause();
    } else {
      unawaited(player.play().catchError((Object _) {}));
    }
    return true;
  }

  Future<void> stop() async {
    _loaded = null;
    await player.stop();
  }

  Future<void> dispose() => player.dispose();
}
