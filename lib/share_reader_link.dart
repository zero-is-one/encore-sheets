import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_deep_link.dart';

Future<void> copyReaderLink(
  BuildContext context,
  ReaderLinkTarget target,
  String id,
) async {
  var message = 'Link copied. It opens the matching item in EncoreSheets.';
  try {
    await Clipboard.setData(
      ClipboardData(text: libraryItemLink(target, id).toString()),
    );
  } catch (_) {
    message = 'Could not copy the link.';
  }
  if (context.mounted)
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
}
