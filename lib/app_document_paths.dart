import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

Future<Directory>? _privateDocuments;

Future<Directory> managedDocuments() =>
    _privateDocuments ??= _openManagedDocuments();

Future<Directory> _openManagedDocuments() async {
  final documents = await getApplicationDocumentsDirectory();
  if (!Platform.isIOS) return documents;
  final support = await getApplicationSupportDirectory();
  final private = await Directory('${support.path}/LibraryData')
      .create(recursive: true);
  final oldScores = Directory('${documents.path}/scores');
  if (await oldScores.exists() &&
      !await Directory('${private.path}/scores').exists()) {
    await oldScores.rename('${private.path}/scores');
  }
  final audio = RegExp(r'^(score-audio-\d+\.[a-z0-9]+|practice-\d+\.m4a)$');
  await for (final item in documents.list(followLinks: false)) {
    if (item is! File) continue;
    final name = item.uri.pathSegments.last;
    if (audio.hasMatch(name) && !await File('${private.path}/$name').exists()) {
      await item.rename('${private.path}/$name');
    }
  }
  return private;
}

Future<Directory> scoreTransferFolder() async {
  final documents = await getApplicationDocumentsDirectory();
  return Directory('${documents.path}/Scores for Transfer')
      .create(recursive: true);
}

Future<List<XFile>> transferScores() async {
  final directory = await scoreTransferFolder();
  final matches = <XFile>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
      matches.add(XFile(entity.path));
    }
  }
  return matches..sort((a, b) => a.name.compareTo(b.name));
}

Future<String> saveTransferScore(XFile source, String filename) async {
  final directory = await scoreTransferFolder();
  final stem = filename.replaceFirst(
    RegExp(r'\.pdf$', caseSensitive: false),
    '',
  );
  var number = 1;
  while (true) {
    final name = number == 1 ? '$stem.pdf' : '$stem ($number).pdf';
    final target = File('${directory.path}/$name');
    try {
      await target.create(exclusive: true);
    } on PathExistsException {
      number++;
      continue;
    }
    try {
      await source.saveTo(target.path);
    } catch (_) {
      await target.delete();
      rethrow;
    }
    return name;
  }
}
