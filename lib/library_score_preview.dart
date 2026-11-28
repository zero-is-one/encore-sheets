import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'score_library.dart';

typedef ScorePreviewPage = ({Uint8List? image, int page, int total});

Future<ScorePreviewPage?> renderLibraryScorePreview(
  ScoreLibrary library,
  ScoreEntry score, {
  int pageNumber = 1,
}) async {
  await pdfrxFlutterInitialize();
  final file = await library.storage.openScore(score.id);
  final document = kIsWeb
      ? await PdfDocument.openData(
          await file.readAsBytes(),
          sourceName: file.name,
        )
      : await PdfDocument.openFile(file.path);
  try {
    final total = document.pages.length;
    if (total == 0) return null;
    final index = pageNumber.clamp(1, total);
    final page = document.pages[index - 1];
    final scale = 360 / math.max(page.width, page.height);
    final width = math.max(1, (page.width * scale).round());
    final height = math.max(1, (page.height * scale).round());
    final pixels = await page.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
    );
    if (pixels == null) return (image: null, page: index, total: total);
    try {
      final image = await pixels.createImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        return (
          image: bytes?.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          ),
          page: index,
          total: total,
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
    required this.options,
  });

  final String title;
  final String subtitle;
  final Future<Uint8List?> preview;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final Widget options;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              InkWell(
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
              PositionedDirectional(
                top: 4,
                end: 4,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Properties for $title',
                        onPressed: onEdit,
                        icon: const Icon(Icons.info_outline),
                      ),
                      options,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
