import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

/// A fitted page followed by a preview is one two-step turn.
({int page, bool preview}) advanceHalfTurn({
  required int page,
  required int first,
  required int last,
  required bool preview,
  required int step,
}) {
  if (step > 0) {
    if (page >= last) return (page: page + 1, preview: false);
    return preview
        ? (page: page + 1, preview: false)
        : (page: page, preview: true);
  }
  if (preview) return (page: page, preview: false);
  if (page <= first) return (page: page, preview: false);
  return (page: page - 1, preview: true);
}

class HalfPageBand extends StatelessWidget {
  const HalfPageBand({
    super.key,
    required this.document,
    required this.page,
    required this.fullSize,
    required this.indicator,
    this.overlay,
    this.tint = Colors.white,
    this.dimming = 0,
  });

  final PdfDocument document;
  final int page;
  final Size fullSize;
  final bool indicator;
  final Widget? overlay;
  final Color tint;
  final double dimming;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: fullSize.width,
          maxWidth: fullSize.width,
          minHeight: fullSize.height,
          maxHeight: fullSize.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.white,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(tint, BlendMode.multiply),
                  child: PdfPageView(
                    document: document,
                    pageNumber: page,
                    decoration: const BoxDecoration(color: Colors.white),
                  ),
                ),
              ),
              if (dimming > 0)
                ColoredBox(color: Colors.black.withValues(alpha: dimming)),
              if (overlay != null) overlay!,
            ],
          ),
        ),
        if (indicator)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ColoredBox(
              color: Color(0xffb3844c),
              child: SizedBox(height: 2),
            ),
          ),
      ],
    ),
  );
}
