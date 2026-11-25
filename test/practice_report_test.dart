import 'dart:io';

import 'package:encoresheets/practice_activity.dart';
import 'package:encoresheets/practice_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  test('both report layouts render recorded titles and totals', () async {
    const activity = <PracticeEntry>[
      (
        selection: (kind: PracticeKind.score, id: 'a', title: 'Étude'),
        day: '2026-11-24',
        seconds: 61,
        views: 2,
      ),
      (
        selection: (kind: PracticeKind.score, id: 'a', title: 'Étude'),
        day: '2026-11-25',
        seconds: 31,
        views: 1,
      ),
    ];
    for (final style in PracticeReportStyle.values) {
      final bytes = await buildPracticeReport(
        history: activity,
        style: style,
        category: 'Scores',
        period: 'Last 7 days',
        generated: DateTime(2026, 11, 25),
      );
      final document = await PdfDocument.openData(bytes);
      addTearDown(document.dispose);
      final text = (await document.pages.single.loadText())?.fullText ?? '';
      expect(text, contains('Étude'));
      if (style == PracticeReportStyle.summary) {
        expect(text, contains('1:32'));
      } else {
        expect(text, contains('2026-11-24'));
        expect(text, contains('0:31'));
      }
    }
  });
}
