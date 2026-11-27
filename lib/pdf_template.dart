import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pdf;

enum ScoreTemplate {
  staff('Staff paper'),
  grandStaff('Grand staff paper'),
  tab('Guitar tablature'),
  lined('Lined paper'),
  blank('Blank paper');

  const ScoreTemplate(this.label);
  final String label;
}

typedef ScoreTemplateConfig = ({
  String title,
  ScoreTemplate style,
  int pages,
  bool letter,
});

Iterable<({double top, double bottom, bool vertical})> _templateLines(
  ScoreTemplate style,
  double height,
) sync* {
  if (style == ScoreTemplate.blank) return;
  final lines = switch (style) {
    ScoreTemplate.staff => 5,
    ScoreTemplate.grandStaff => 10,
    ScoreTemplate.tab => 6,
    _ => 1,
  };
  final gap = style == ScoreTemplate.lined ? 20 : 7;
  final groupGap = switch (style) {
    ScoreTemplate.grandStaff => 112,
    ScoreTemplate.lined => 20,
    _ => 66,
  };
  for (var top = 14.0; height - top >= 12 + lines * gap; top += groupGap) {
    for (var line = 0; line < lines; line++) {
      final staffGap = style == ScoreTemplate.grandStaff && line >= 5 ? 15 : 0;
      final position = top + line * gap + staffGap;
      yield (top: position, bottom: position, vertical: false);
    }
    if (style == ScoreTemplate.grandStaff) {
      yield (top: top, bottom: top + 9 * gap + 15, vertical: true);
    }
  }
}

Future<Uint8List> createTemplatePdf(ScoreTemplateConfig layout) {
  if (layout.pages < 1 || layout.pages > 100) {
    throw ArgumentError.value(layout.pages, 'pages');
  }
  final format = layout.letter ? PdfPageFormat.letter : PdfPageFormat.a4;
  final document = pdf.Document(title: layout.title);
  for (var page = 0; page < layout.pages; page++) {
    document.addPage(
      pdf.Page(
        pageFormat: format,
        margin: const pdf.EdgeInsets.all(40),
        build: (_) => pdf.CustomPaint(
          size: PdfPoint(format.width - 80, format.height - 80),
          painter: (canvas, size) {
            canvas.setLineWidth(0.5);
            canvas.setStrokeColor(PdfColors.grey800);
            for (final line in _templateLines(layout.style, size.y)) {
              canvas.drawLine(
                0,
                size.y - line.top,
                line.vertical ? 0 : size.x,
                size.y - line.bottom,
              );
            }
            canvas.strokePath();
          },
        ),
      ),
    );
  }
  return document.save();
}

class ScoreTemplateDialog extends StatefulWidget {
  const ScoreTemplateDialog({super.key});

  @override
  State<ScoreTemplateDialog> createState() => _ScoreTemplateDialogState();
}

class _ScoreTemplateDialogState extends State<ScoreTemplateDialog> {
  final _title = TextEditingController();
  final _pages = TextEditingController(text: '1');
  ScoreTemplate _style = ScoreTemplate.staff;
  bool _letter = false;
  bool _invalid = false;

  @override
  void dispose() {
    _title.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _create() {
    final pages = int.tryParse(_pages.text.trim());
    if (pages == null || pages < 1 || pages > 100) {
      setState(() => _invalid = true);
      return;
    }
    final title = _title.text.trim();
    Navigator.pop(context, (
      title: title.isEmpty ? _style.label : title,
      style: _style,
      pages: pages,
      letter: _letter,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create score from template'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
          maxLength: 100,
        ),
        DropdownButton<ScoreTemplate>(
          value: _style,
          items: [
            for (final style in ScoreTemplate.values)
              DropdownMenuItem(value: style, child: Text(style.label)),
          ],
          onChanged: (value) => setState(() => _style = value!),
        ),
        Center(
          child: Semantics(
            image: true,
            label: '${_style.label} preview',
            child: SizedBox(
              height: 130,
              child: AspectRatio(
                aspectRatio: _letter ? 8.5 / 11 : 210 / 297,
                child: CustomPaint(painter: _TemplatePreview(_style, _letter)),
              ),
            ),
          ),
        ),
        TextField(
          controller: _pages,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Pages',
            errorText: _invalid ? 'Enter a number from 1 to 100' : null,
          ),
        ),
        DropdownButton<bool>(
          value: _letter,
          items: const [
            DropdownMenuItem(value: false, child: Text('A4')),
            DropdownMenuItem(value: true, child: Text('US Letter')),
          ],
          onChanged: (value) => setState(() => _letter = value!),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _create, child: const Text('Create')),
    ],
  );
}

class _TemplatePreview extends CustomPainter {
  const _TemplatePreview(this.style, this.letter);

  final ScoreTemplate style;
  final bool letter;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final format = letter ? PdfPageFormat.letter : PdfPageFormat.a4;
    final scale = size.height / format.height;
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = .5;
    final left = 40 * scale;
    for (final line in _templateLines(style, format.height - 80)) {
      canvas.drawLine(
        Offset(left, (40 + line.top) * scale),
        Offset(
          line.vertical ? left : size.width - left,
          (40 + line.bottom) * scale,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TemplatePreview oldDelegate) =>
      oldDelegate.style != style || oldDelegate.letter != letter;
}
