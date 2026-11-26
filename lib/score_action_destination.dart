import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'score_action.dart';
import 'score_library.dart';

bool get supportsExternalScoreFiles =>
    !kIsWeb &&
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
    }.contains(defaultTargetPlatform);

Future<String> storeScoreActionFile(XFile source) async {
  final name = source.name
      .split(RegExp(r'[/\\]'))
      .last
      .replaceAll(RegExp(r'[<>:"|?*\x00-\x1f\x7f]'), '_');
  final reference = '${ScoreLibrary.newRecordId()}/$name';
  final parts = ScoreAction.fileReference(reference);
  if (parts == null)
    throw const FormatException('Unsupported file type or name');
  final support = await getApplicationSupportDirectory();
  final folder = await Directory(
    '${support.path}/score-action-files/${parts.id}',
  ).create(recursive: true);
  try {
    await source.saveTo('${folder.path}/${parts.name}');
  } catch (_) {
    await folder.delete(recursive: true);
    rethrow;
  }
  return reference;
}

Future<bool> openScoreActionDestination(ScoreAction action) async {
  if (action.kind == ScoreActionKind.externalFile) {
    final file = ScoreAction.fileReference(action.parameter);
    if (!supportsExternalScoreFiles || file == null) return false;
    return await const MethodChannel('encoresheets/score-action-file')
            .invokeMethod<bool>('open', {'id': file.id, 'name': file.name}) ??
        false;
  }
  final uri = ScoreAction.destinationUri(action.kind, action.parameter);
  if (uri == null || kIsWeb && action.kind == ScoreActionKind.externalApp)
    return false;
  return launchUrl(
    uri,
    mode: action.kind == ScoreActionKind.externalApp && uri.scheme == 'https'
        ? LaunchMode.externalNonBrowserApplication
        : LaunchMode.externalApplication,
  );
}
