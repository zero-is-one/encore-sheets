import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

typedef MeasureClip = ({Uint8List png, double width, double height});

Future<MeasureClip> copyMeasure(PdfPage page, Rect area) async {
  final scale = math.min(
    3.0,
    1700 / math.max(page.width * area.width, page.height * area.height),
  );
  final fullWidth = page.width * scale;
  final fullHeight = page.height * scale;
  final pixels = await page.render(
    x: (area.left * fullWidth).floor(),
    y: (area.top * fullHeight).floor(),
    width: math.max(1, (area.width * fullWidth).floor()),
    height: math.max(1, (area.height * fullHeight).floor()),
    fullWidth: fullWidth,
    fullHeight: fullHeight,
    annotationRenderingMode: PdfAnnotationRenderingMode.none,
  );
  if (pixels == null) throw StateError('Could not read the selected measure.');
  try {
    final image = await pixels.createImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || data.lengthInBytes > 3 * 1024 * 1024) {
        throw StateError('Choose a smaller section of the score.');
      }
      return (
        png: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: area.width * page.width,
        height: area.height * page.height,
      );
    } finally {
      image.dispose();
    }
  } finally {
    pixels.dispose();
  }
}

class MeasureRegionDialog extends StatefulWidget {
  const MeasureRegionDialog({super.key, required this.page, this.clip});
  final PdfPage page;
  final MeasureClip? clip;

  @override
  State<MeasureRegionDialog> createState() => _MeasureRegionDialogState();
}

class _MeasureRegionDialogState extends State<MeasureRegionDialog> {
  Rect? _area;
  Offset? _start;

  Offset _normalized(Offset at, Size size) => Offset(
    (at.dx / size.width).clamp(0.0, 1.0),
    (at.dy / size.height).clamp(0.0, 1.0),
  );

  Rect _placement(Offset point) {
    final clip = widget.clip!;
    final scale = math.min(
      1.0,
      math.min(
        widget.page.width / clip.width,
        widget.page.height / clip.height,
      ),
    );
    final width = scale * clip.width / widget.page.width;
    final height = scale * clip.height / widget.page.height;
    return Rect.fromLTWH(
      point.dx.clamp(0, 1 - width),
      point.dy.clamp(0, 1 - height),
      width,
      height,
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.clip == null ? 'Copy a measure' : 'Place copied measure',
    ),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.clip == null
                ? 'Drag around the music to copy.'
                : 'Tap or drag to position the copy.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 350,
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.page.width / widget.page.height,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: widget.clip == null
                          ? null
                          : (event) => setState(
                              () => _area = _placement(
                                _normalized(event.localPosition, size),
                              ),
                            ),
                      onPanStart: (event) =>
                          _start = _normalized(event.localPosition, size),
                      onPanUpdate: (event) {
                        final point = _normalized(event.localPosition, size);
                        setState(
                          () => _area = widget.clip == null
                              ? Rect.fromPoints(_start ?? point, point)
                              : _placement(point),
                        );
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PdfPageView(
                            document: widget.page.document,
                            pageNumber: widget.page.pageNumber,
                            maximumDpi: 110,
                          ),
                          if (_area case final area?)
                            Positioned.fromRect(
                              rect: Rect.fromLTWH(
                                area.left * size.width,
                                area.top * size.height,
                                area.width * size.width,
                                area.height * size.height,
                              ),
                              child: widget.clip == null
                                  ? Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0x44814acf),
                                        border: Border.all(
                                          color: const Color(0xff814acf),
                                          width: 2,
                                        ),
                                      ),
                                    )
                                  : Image.memory(
                                      widget.clip!.png,
                                      fit: BoxFit.fill,
                                    ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _area == null || _area!.width < .006 || _area!.height < .006
            ? null
            : () => Navigator.pop(context, _area),
        child: Text(widget.clip == null ? 'Copy' : 'Place'),
      ),
    ],
  );
}
