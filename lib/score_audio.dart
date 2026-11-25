import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'score_library.dart';
import 'audio_page_cues.dart';

typedef LinkedAudio = ({String? file, String? musicId, String name});

class ScoreAudioSession {
  ScoreAudioSession(this.library);
  final ScoreLibrary library;
  final player = AudioPlayer();
  String? _loaded;
  String? _playingMusicId;
  static const _music = MethodChannel('encoresheets/music');
  String? pinnedSelection;
  Duration? loopStart;
  Duration? loopEnd;
  bool get looping => loopEnd != null;
  String? get loadedFile => _loaded;
  Duration get timelinePosition =>
      player.position + (looping ? loopStart ?? Duration.zero : Duration.zero);

  Future<List<AudioPageCue>> pageCues(String file) async {
    final prefs = await library.storage.readPreferences();
    return readAudioPageCues((prefs['audioPageCues'] as Map?)?[file]);
  }

  Future<void> savePageCues(String file, List<AudioPageCue> cues) async {
    final prefs = await library.storage.readPreferences();
    final all = Map<String, dynamic>.from(prefs['audioPageCues'] as Map? ?? {});
    if (cues.isEmpty) {
      all.remove(file);
    } else {
      all[file] = [
        for (final cue in cues) {'ms': cue.milliseconds, 'page': cue.page},
      ];
    }
    await library.updatePreferences({'audioPageCues': all});
  }

  static bool get supported =>
      !kIsWeb &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  static bool get supportsPitch =>
      supported && defaultTargetPlatform == TargetPlatform.android;
  static bool get supportsMusic =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<String> _folder() async =>
      (await getApplicationDocumentsDirectory()).path;

  Future<Map<String, dynamic>> _attachments() async {
    final preferences = await library.storage.readPreferences();
    return (preferences['localScoreAudio'] as Map?)?.cast<String, dynamic>() ??
        {};
  }

  Future<LinkedAudio?> track(String selection) async {
    final data = (await _attachments())[selection];
    if (data case {'file': final String file, 'name': final String name}
        when RegExp(r'^score-audio-[0-9]+\.[a-z0-9]+$').hasMatch(file)) {
      return (file: file, name: name, musicId: null);
    }
    if (data case {'musicId': final String id, 'name': final String name}
        when supportsMusic && RegExp(r'^\d{1,20}$').hasMatch(id)) {
      return (file: null, name: name, musicId: id);
    }
    return null;
  }

  Future<bool> attachMusic(String selection) async {
    if (!supportsMusic) return false;
    final picked = await _music.invokeMapMethod<String, String>('pick');
    if (picked == null) return false;
    final previous = await track(selection);
    final attachments = await _attachments();
    await stop();
    await library.updatePreferences({
      'localScoreAudio': {
        ...attachments,
        selection: {'musicId': picked['id'], 'name': picked['title']},
      },
    });
    if (previous?.file case final file?)
      await _discard('${await _folder()}/$file');
    return true;
  }

  Future<bool> musicPlaying(String id) async =>
      await _music.invokeMethod<bool>('isPlaying', id) ?? false;

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
      await _stopMusic();
      await player.setLoopMode(LoopMode.off);
      await player.setFilePath(path);
      loopStart = loopEnd = null;
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
    if (previous?.file case final old?) await _discard('$folder/$old');
  }

  Future<void> unlink(String selection) async {
    final previous = await track(selection);
    final attachments = await _attachments();
    attachments.remove(selection);
    await library.updatePreferences({'localScoreAudio': attachments});
    await stop();
    if (previous?.file case final old?)
      await _discard('${await _folder()}/$old');
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
    final file = found.file;
    if (file == null) {
      if (_loaded != null) await player.stop();
      _loaded = null;
      if (_playingMusicId != found.musicId) await _stopMusic();
      return true;
    }
    await _stopMusic();
    if (_loaded != file) {
      await player.setLoopMode(LoopMode.off);
      await player.setFilePath('${await _folder()}/$file');
      _loaded = file;
      loopStart = loopEnd = null;
      if (pinnedSelection != selection) pinnedSelection = null;
    }
    return true;
  }

  void markLoopStart() {
    if (!looping) loopStart = player.position;
  }

  Future<void> markLoopEnd() async {
    final start = loopStart;
    final end = player.position;
    if (start == null || end - start < const Duration(milliseconds: 150)) {
      throw const FormatException('Set B at least 150 ms after A.');
    }
    await player.setClip(start: start, end: end);
    await player.setLoopMode(LoopMode.one);
    await player.seek(Duration.zero);
    loopEnd = end;
  }

  Future<void> clearLoop() async {
    final start = loopStart;
    if (looping) {
      await player.setLoopMode(LoopMode.off);
      await player.setClip();
      if (start != null) await player.seek(start);
    }
    loopStart = loopEnd = null;
  }

  Future<bool> toggle(String selection) async {
    if (!await open(selection)) return false;
    final musicId = (await track(selection))?.musicId;
    if (musicId != null) {
      await _music.invokeMethod<bool>('toggle', musicId);
      _playingMusicId = musicId;
      return true;
    }
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
    pinnedSelection = null;
    loopStart = loopEnd = null;
    await player.stop();
    await _stopMusic();
  }

  Future<void> _stopMusic() async {
    if (_playingMusicId == null) return;
    await _music.invokeMethod<void>('stop');
    _playingMusicId = null;
  }

  Future<void> pause() async {
    await player.pause();
    if (_playingMusicId != null) await _music.invokeMethod<void>('pause');
  }

  Future<void> playTake(String path) async {
    await stop();
    await player.setLoopMode(LoopMode.off);
    await player.setSpeed(1);
    if (supportsPitch) await player.setPitch(1);
    await player.setFilePath(path);
    unawaited(player.play().catchError((Object _) {}));
  }

  Future<void> dispose() => player.dispose().whenComplete(_stopMusic);
}
