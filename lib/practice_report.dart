import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pdf;

import 'practice_activity.dart';
import 'pdf_text_font.dart';

enum PracticeReportStyle {
  summary('Summary by item'),
  log('Daily activity log');

  const PracticeReportStyle(this.label);
  final String label;
}

Future<Uint8List> buildPracticeReport({
  required Iterable<PracticeEntry> history,
  required PracticeReportStyle style,
  required String period,
  required String category,
  required DateTime generated,
}) async {
  final totals = <String, ({String title, int seconds, int views})>{};
  final entries = history.toList()..sort((a, b) => b.day.compareTo(a.day));
  if (style == PracticeReportStyle.summary) {
    for (final row in entries) {
      final id = row.selection.id;
      final old = totals[id];
      totals[id] = (
        title: old?.title ?? row.selection.title,
        seconds: (old?.seconds ?? 0) + row.seconds,
        views: (old?.views ?? 0) + row.views,
      );
    }
  }
  String clock(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }

  String fit(String text) =>
      text.length > 150 ? '${text.substring(0, 147)}...' : text;
  final data = style == PracticeReportStyle.summary
      ? [
          for (final item in totals.values)
            [fit(item.title), clock(item.seconds), '${item.views}'],
        ]
      : [
          for (final item in entries)
            [
              item.day,
              fit(item.selection.title),
              clock(item.seconds),
              '${item.views}',
            ],
        ];

  final document = pdf.Document(
    title: 'EncoreSheets practice report',
    theme: pdf.ThemeData.withFont(base: pdf.Font.ttf(await loadPdfTextFont())),
  );
  document.addPage(
    pdf.MultiPage(
      maxPages: 500,
      pageFormat: PdfPageFormat.a4,
      margin: const pdf.EdgeInsets.all(36),
      header: (context) => pdf.Container(
        margin: const pdf.EdgeInsets.only(bottom: 14),
        child: pdf.Column(
          crossAxisAlignment: pdf.CrossAxisAlignment.start,
          children: [
            pdf.Text(
              'EncoreSheets practice report',
              style: const pdf.TextStyle(fontSize: 20),
            ),
            pdf.Text('$category / $period / ${style.label}'),
            pdf.Text('Generated ${practiceDay(generated)}'),
          ],
        ),
      ),
      footer: (context) => pdf.Align(
        alignment: pdf.Alignment.centerRight,
        child: pdf.Text('Page ${context.pageNumber} of ${context.pagesCount}'),
      ),
      build: (_) => [
        if (data.isEmpty) pdf.Text('No practice recorded for this view.'),
        if (data.isNotEmpty)
          pdf.TableHelper.fromTextArray(
            headers: [
              if (style == PracticeReportStyle.log) 'Date',
              'Item',
              'Time (min:sec)',
              'Views',
            ],
            data: data,
            headerDecoration: const pdf.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pdf.TextStyle(fontSize: 10),
          ),
      ],
    ),
  );
  return document.save();
}
