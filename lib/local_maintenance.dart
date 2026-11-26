import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Removes old working copies created in this app's private cache.
Future<int> cleanOldWorkingFiles() async {
  final root = await getTemporaryDirectory();
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  final names = RegExp(
    r'^(encoresheets-package-|encoresheets-setlist-|score-import-|pdf-import-|encore-keys-|encore-click-)',
  );
  var removed = 0;
  await for (final item in root.list(followLinks: false)) {
    if (item is! File && item is! Directory) continue;
    final basename = item.uri.pathSegments
        .where((part) => part.isNotEmpty)
        .last;
    if (!names.hasMatch(basename)) continue;
    try {
      final stat = await item.stat();
      if (!stat.modified.isBefore(cutoff)) continue;
      await item.delete(recursive: item is Directory);
      removed++;
    } on FileSystemException {
      // A concurrent operation may already have removed this copy.
    }
  }
  return removed;
}
