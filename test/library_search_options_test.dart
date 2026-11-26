import 'package:encoresheets/library_search_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orders visible search groups without losing their source indices', () {
    final options = LibrarySearchOptions.fromJson({
      'groups': ['setlists', 'scores', 'invalid', 'setlists'],
      'hidden': ['bookmarks'],
      'ignoreArticles': true,
    });
    expect(
      options.orderedResults({
        LibraryResultGroup.scores: 2,
        LibraryResultGroup.bookmarks: 1,
        LibraryResultGroup.setlists: 2,
        LibraryResultGroup.actions: 1,
      }),
      [3, 4, 0, 1, 5],
    );
    expect(options.titleKey('The Sonata'), 'sonata');
  });
}
