import 'package:encoresheets/reader_restrictions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the reader stores salted verification and rejects a different passcode',
    () async {
      final original = await ReaderRestrictions.create('504918', {
        RestrictedTool.markup,
      });
      final saved = original.toJson();
      expect(saved.values, isNot(contains('504918')));
      final restored = ReaderRestrictions.fromJson(saved)!;
      expect(restored.tools, {RestrictedTool.markup});
      expect(await restored.permits('504918'), isTrue);
      expect(await restored.permits('504919'), isFalse);
    },
  );
}
