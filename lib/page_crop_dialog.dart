import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'page_crop.dart';

enum PageCropScope { current, allLikeCurrent, autoAll, resetAll }

class PageCropDialog extends StatefulWidget {
  const PageCropDialog({super.key, required this.page, this.initial});

  final PdfPage page;
  final PageCrop? initial;

  @override
  State<PageCropDialog> createState() => _PageCropDialogState();
}

class _PageCropDialogState extends State<PageCropDialog> {
  late PageCrop _crop = widget.initial ?? const PageCrop();
  bool _working = false;
  bool _grid = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) _autoFit();
  }

  Future<void> _autoFit() async {
    setState(() => _working = true);
    try {
      final suggested = await detectPageMargins(widget.page);
      if (mounted)
        setState(() => _crop = suggested.copyWith(angle: _crop.angle));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not detect this page’s margins.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _slider(
    String name,
    double value,
    ValueChanged<double> onChanged, {
    bool angle = false,
  }) => Row(
    children: [
      SizedBox(width: 64, child: Text(name)),
      Expanded(
        child: Slider(
          value: value,
          min: angle ? -PageCrop.maxAngle : 0,
          max: angle ? PageCrop.maxAngle : PageCrop.maxMargin,
          onChanged: _working
              ? null
              : (value) => setState(() => onChanged(value)),
          onChangeStart: angle ? (_) => setState(() => _grid = true) : null,
          onChangeEnd: angle ? (_) => setState(() => _grid = false) : null,
        ),
      ),
      SizedBox(
        width: 44,
        child: Text(
          angle ? '${value.toStringAsFixed(1)}°' : '${(value * 100).round()}%',
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    return AlertDialog(
      title: Text('Crop page ${page.pageNumber}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 190,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: page.width / page.height,
                    child: ClipRect(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Transform.rotate(
                            angle: _crop.angle * math.pi / 180,
                            child: PdfPageView(
                              document: page.document,
                              pageNumber: page.pageNumber,
                              maximumDpi: 75,
                            ),
                          ),
                          CustomPaint(painter: _CropGuide(_crop, grid: _grid)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_working) const LinearProgressIndicator(),
              _slider(
                'Left',
                _crop.left,
                (v) => _crop = _crop.copyWith(left: v),
              ),
              _slider(
                'Right',
                _crop.right,
                (v) => _crop = _crop.copyWith(right: v),
              ),
              _slider('Top', _crop.top, (v) => _crop = _crop.copyWith(top: v)),
              _slider(
                'Bottom',
                _crop.bottom,
                (v) => _crop = _crop.copyWith(bottom: v),
              ),
              _slider(
                'Deskew',
                _crop.angle,
                (v) => _crop = _crop.copyWith(angle: v),
                angle: true,
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: _working ? null : _autoFit,
                    child: const Text('Auto fit'),
                  ),
                  TextButton(
                    onPressed: _working || _crop.angle == 0
                        ? null
                        : () =>
                              setState(() => _crop = _crop.copyWith(angle: 0)),
                    child: const Text('Reset angle'),
                  ),
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => setState(() => _crop = const PageCrop()),
                    child: const Text('Reset page'),
                  ),
                  PopupMenuButton<PageCropScope>(
                    tooltip: 'Batch crop',
                    enabled: !_working,
                    onSelected: (scope) =>
                        Navigator.pop(context, (scope, _crop)),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: PageCropScope.allLikeCurrent,
                        child: Text('Apply to every page'),
                      ),
                      PopupMenuItem(
                        value: PageCropScope.autoAll,
                        child: Text('Auto fit every page'),
                      ),
                      PopupMenuItem(
                        value: PageCropScope.resetAll,
                        child: Text('Reset every page'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _working
              ? null
              : () => Navigator.pop(context, (PageCropScope.current, _crop)),
          child: const Text('Save crop'),
        ),
      ],
    );
  }
}

class _CropGuide extends CustomPainter {
  _CropGuide(this.crop, {required this.grid});

  final PageCrop crop;
  final bool grid;

  @override
  void paint(Canvas canvas, Size size) {
    final page = Offset.zero & size;
    final visible = crop.within(page);
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(page)
      ..addRect(visible);
    canvas.drawPath(mask, Paint()..color = const Color(0x99000000));
    final guide = Paint()
      ..color = const Color(0xff3271eb)
      ..strokeWidth = 1;
    guide.style = PaintingStyle.stroke;
    canvas.drawRect(visible, guide);
    if (grid) {
      for (var row = 1; row <= 6; row++) {
        final y = visible.top + row * visible.height / 7;
        canvas.drawLine(
          Offset(visible.left, y),
          Offset(visible.right, y),
          guide,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CropGuide oldDelegate) =>
      oldDelegate.crop != crop || oldDelegate.grid != grid;
}
