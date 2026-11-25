import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker;
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_rearrange.dart';
import 'scan_cleanup.dart';
import 'score_library.dart';

class ScanCleanupScreen extends StatefulWidget {
  const ScanCleanupScreen({super.key, required this.library, this.cameraPdf});

  final ScoreLibrary library;
  final XFile? cameraPdf;

  @override
  State<ScanCleanupScreen> createState() => _ScanCleanupScreenState();
}

class _ScanCleanupScreenState extends State<ScanCleanupScreen> {
  final _title = TextEditingController(text: 'Scanned score');
  final _pages = <({String name, Uint8List bytes, ScanEdits edits})>[];
  int _index = 0;
  int _corner = 0;
  bool _busy = false;
  String? _message;
  Uint8List? _preview;

  @override
  void initState() {
    super.initState();
    if (widget.cameraPdf != null) _run(_loadCamera);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted)
        setState(
          () => _message = error is FormatException
              ? error.message
              : 'Could not process the selected pages.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadCamera() async {
    final document = await openRearrangeDocument(widget.cameraPdf!);
    try {
      for (final page in document.pages) {
        if (!mounted) return;
        final scale = 2300 / math.max(page.width, page.height);
        final rendered = await page.render(
          width: math.max(1, (page.width * scale).round()),
          height: math.max(1, (page.height * scale).round()),
        );
        if (rendered == null)
          throw const FormatException('A capture could not be opened.');
        try {
          final image = await rendered.createImage();
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            if (data == null)
              throw const FormatException('A capture could not be decoded.');
            _pages.add((
              name: 'Capture ${page.pageNumber}',
              bytes: data.buffer.asUint8List(
                data.offsetInBytes,
                data.lengthInBytes,
              ),
              edits: const ScanEdits(),
            ));
          } finally {
            image.dispose();
          }
        } finally {
          rendered.dispose();
        }
      }
    } finally {
      await document.dispose();
    }
  }

  Future<void> _addImages({bool photos = false}) => _run(() async {
    final files = photos
        ? await ImagePicker().pickMultiImage(
            maxWidth: 2600,
            maxHeight: 2600,
            imageQuality: 95,
            requestFullMetadata: false,
          )
        : await openFiles(
            acceptedTypeGroups: const [
              XTypeGroup(
                label: 'Images',
                extensions: [
                  'jpg',
                  'jpeg',
                  'png',
                  'webp',
                  'gif',
                  'bmp',
                  'tif',
                  'tiff',
                ],
                mimeTypes: ['image/*'],
                uniformTypeIdentifiers: ['public.image'],
              ),
            ],
          );
    final skipped = <String>[];
    for (final file in files) {
      if (!mounted) return;
      try {
        final bytes = await compute(prepareScanImage, await file.readAsBytes());
        _pages.add((name: file.name, bytes: bytes, edits: const ScanEdits()));
      } catch (_) {
        skipped.add(file.name);
      }
    }
    if (skipped.isNotEmpty) {
      throw FormatException('Could not open ${skipped.join(', ')}.');
    }
  });

  void _change(ScanEdits edits) => setState(() {
    final row = _pages[_index];
    _pages[_index] = (name: row.name, bytes: row.bytes, edits: edits);
    _preview = null;
  });

  Future<void> _previewPage() => _run(() async {
    final row = _pages[_index];
    final small = await compute(
      (bytes) => prepareScanImage(bytes, limit: 650),
      row.bytes,
    );
    final preview = await compute(_renderPreview, (
      bytes: small,
      edits: row.edits,
    ));
    if (mounted) setState(() => _preview = preview);
  });

  Future<void> _save() => _run(() async {
    final title = _title.text.trim();
    if (title.isEmpty) throw const FormatException('Enter a score name.');
    final pages = [
      for (final row in _pages) (bytes: row.bytes, edits: row.edits),
    ];
    final bytes = await compute(buildScannedPdf, pages);
    final (score, _) = await widget.library.import(
      XFile.fromData(bytes, name: '$title.pdf', mimeType: 'application/pdf'),
    );
    if (mounted) Navigator.pop(context, score);
  });

  void _move(int delta) => setState(() {
    _pages.insert(_index + delta, _pages.removeAt(_index));
    _index += delta;
  });

  Widget _slider(
    String title,
    double value,
    double maximum,
    ValueChanged<double> update,
  ) => Row(
    children: [
      SizedBox(width: 88, child: Text(title)),
      Expanded(
        child: Slider(
          value: value,
          max: maximum,
          divisions: 100,
          label: '${(value * 100).round()}%',
          onChanged: _busy ? null : update,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final row = _pages.isEmpty ? null : _pages[_index];
    final edits = row?.edits;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Scan cleanup')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _title,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Score name'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy ? null : _addImages,
                    child: const Text('Add from Files'),
                  ),
                  if (!kIsWeb &&
                      (defaultTargetPlatform == TargetPlatform.iOS ||
                          defaultTargetPlatform == TargetPlatform.android))
                    TextButton(
                      onPressed: _busy ? null : () => _addImages(photos: true),
                      child: const Text('Add from Photos'),
                    ),
                  FilledButton(
                    onPressed: _busy || row == null ? null : _save,
                    child: const Text('Save PDF'),
                  ),
                ],
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_message case final message?) Text(message),
              if (row != null && edits != null) ...[
                DropdownButton<int>(
                  value: _index,
                  isExpanded: true,
                  onChanged: _busy
                      ? null
                      : (index) => setState(() {
                          _index = index!;
                          _preview = null;
                        }),
                  items: [
                    for (final (index, page) in _pages.indexed)
                      DropdownMenuItem(
                        value: index,
                        child: Text(
                          '${index + 1}. ${page.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy || _index == 0 ? null : () => _move(-1),
                      child: const Text('Move earlier'),
                    ),
                    TextButton(
                      onPressed: _busy || _index + 1 == _pages.length
                          ? null
                          : () => _move(1),
                      child: const Text('Move later'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _pages.removeAt(_index);
                              _index = math.max(
                                0,
                                math.min(_index, _pages.length - 1),
                              );
                              _preview = null;
                            }),
                      child: const Text('Remove page'),
                    ),
                  ],
                ),
                SizedBox(
                  height: 280,
                  child: _preview == null
                      ? CustomPaint(
                          foregroundPainter: _ScanCropGuide(
                            row.bytes,
                            edits.corners,
                            _corner,
                          ),
                          child: Image.memory(row.bytes, fit: BoxFit.contain),
                        )
                      : Image.memory(_preview!, fit: BoxFit.contain),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _change(
                              edits.copyWith(
                                rotation: (edits.rotation + 1) % 4,
                              ),
                            ),
                      child: Text('Rotate · ${edits.rotation * 90}°'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : _preview == null
                          ? _previewPage
                          : () => setState(() => _preview = null),
                      child: Text(
                        _preview == null
                            ? 'Preview cleanup'
                            : 'Show crop guide',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _change(const ScanEdits()),
                      child: const Text('Reset page'),
                    ),
                  ],
                ),
                DropdownButton<int>(
                  value: _corner,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _corner = value!;
                          _preview = null;
                        }),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Top left corner')),
                    DropdownMenuItem(value: 1, child: Text('Top right corner')),
                    DropdownMenuItem(
                      value: 2,
                      child: Text('Bottom right corner'),
                    ),
                    DropdownMenuItem(
                      value: 3,
                      child: Text('Bottom left corner'),
                    ),
                  ],
                ),
                _slider(
                  'Horizontal',
                  edits.corners[_corner].x,
                  1,
                  (value) => _setCorner(edits, x: value),
                ),
                _slider(
                  'Vertical',
                  edits.corners[_corner].y,
                  1,
                  (value) => _setCorner(edits, y: value),
                ),
                _slider(
                  'Brightness',
                  edits.brightness,
                  2,
                  (value) => _change(edits.copyWith(brightness: value)),
                ),
                _slider(
                  'Contrast',
                  edits.contrast,
                  2,
                  (value) => _change(edits.copyWith(contrast: value)),
                ),
                _slider(
                  'Saturation',
                  edits.saturation,
                  2,
                  (value) => _change(edits.copyWith(saturation: value)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _setCorner(ScanEdits edits, {double? x, double? y}) {
    final corners = [...edits.corners];
    final point = corners[_corner];
    corners[_corner] = (x: x ?? point.x, y: y ?? point.y);
    _change(edits.copyWith(corners: corners));
  }
}

Uint8List _renderPreview(({Uint8List bytes, ScanEdits edits}) page) =>
    correctScanPage(page.bytes, page.edits).bytes;

class _ScanCropGuide extends CustomPainter {
  _ScanCropGuide(this.png, this.corners, this.selected);

  final Uint8List png;
  final List<ScanPoint> corners;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    final header = ByteData.sublistView(png);
    final width = header.getUint32(16).toDouble();
    final height = header.getUint32(20).toDouble();
    final scale = math.min(size.width / width, size.height / height);
    final image = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: width * scale,
      height: height * scale,
    );
    final points = [
      for (final p in corners)
        Offset(image.left + p.x * image.width, image.top + p.y * image.height),
    ];
    final paint = Paint()
      ..color = const Color(0xff3271eb)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..addPolygon(points, true), paint);
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(points[selected], 6, paint);
  }

  @override
  bool shouldRepaint(_ScanCropGuide old) =>
      png != old.png || corners != old.corners || selected != old.selected;
}
