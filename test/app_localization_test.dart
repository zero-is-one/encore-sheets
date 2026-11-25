import 'package:encoresheets/app_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('each advertised reader locale has localized platform controls', () {
    expect(readerLocales, hasLength(24));
    for (final locale in readerLocales) {
      expect(GlobalMaterialLocalizations.delegate.isSupported(locale), isTrue);
      expect(readerLanguageNames[locale.languageCode], isNotNull);
    }
  });

  testWidgets('Arabic reader copy follows right-to-left direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: readerLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => Text(
            ReaderText.library.of(context),
            key: const ValueKey('reader-label'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('مكتبة النوتات'), findsOneWidget);
    final context = tester.element(find.byKey(const ValueKey('reader-label')));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
