enum SetlistOrder {
  manual('Manual order'),
  title('Title'),
  leastRecent('Least recently played'),
  shuffle('Shuffle');

  const SetlistOrder(this.label);
  final String label;
}

List<T> orderSetlistItems<T>(
  Iterable<T> items,
  SetlistOrder order, {
  required String Function(T) title,
  required int? Function(T) lastPlayed,
}) {
  final rows = items.indexed.toList();
  switch (order) {
    case SetlistOrder.manual:
      break;
    case SetlistOrder.shuffle:
      rows.shuffle();
    case SetlistOrder.title:
    case SetlistOrder.leastRecent:
      rows.sort((a, b) {
        final comparison = order == SetlistOrder.title
            ? title(a.$2).toLowerCase().compareTo(title(b.$2).toLowerCase())
            : (lastPlayed(a.$2) ?? 0).compareTo(lastPlayed(b.$2) ?? 0);
        return comparison == 0 ? a.$1.compareTo(b.$1) : comparison;
      });
  }
  return [for (final row in rows) row.$2];
}
