import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'score_library.dart';

Future<Uint8List?> renderLibraryScorePreview(
  ScoreLibrary library,
  ScoreEntry score,
) async {
  await pdfrxFlutterInitialize();
  final file = await library.storage.openScore(score.id);
  final document = kIsWeb
      ? await PdfDocument.openData(
          await file.readAsBytes(),
          sourceName: file.name,
        )
      : await PdfDocument.openFile(file.path);
  try {
    final page = document.pages.first;
    final scale = 360 / math.max(page.width, page.height);
    final width = math.max(1, (page.width * scale).round());
    final height = math.max(1, (page.height * scale).round());
    final pixels = await page.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
    );
    if (pixels == null) return null;
    try {
      final image = await pixels.createImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        return bytes?.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      } finally {
        image.dispose();
      }
    } finally {
      pixels.dispose();
    }
  } finally {
    await document.dispose();
  }
}

class LibraryScorePreview extends StatelessWidget {
  const LibraryScorePreview({
    super.key,
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.onOpen,
    required this.onEdit,
  });

  final String title;
  final String subtitle;
  final Future<Uint8List?> preview;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: InkWell(
            onTap: onOpen,
            child: FutureBuilder<Uint8List?>(
              future: preview,
              builder: (context, snapshot) {
                final data = snapshot.data;
                return data == null
                    ? const Center(child: Icon(Icons.description_outlined))
                    : Image.memory(
                        data,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                      );
              },
            ),
          ),
        ),
        ListTile(
          dense: true,
          onTap: onOpen,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: subtitle.isEmpty
              ? null
              : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: 'Properties for $title',
            onPressed: onEdit,
            icon: const Icon(Icons.info_outline),
          ),
        ),
      ],
    ),
  );
}
