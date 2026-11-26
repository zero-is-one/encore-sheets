import 'package:material_ui/material_ui.dart';

enum LibraryResultGroup {
  scores('Scores'),
  bookmarks('Bookmarks'),
  setlists('Setlists'),
  actions('Library actions');

  const LibraryResultGroup(this.label);
  final String label;
}

class LibrarySearchOptions {
  const LibrarySearchOptions({
    this.groups = LibraryResultGroup.values,
    this.hidden = const {},
    this.recentLimit = 0,
    this.ignoreArticles = false,
  });

  factory LibrarySearchOptions.fromJson(Object? stored) {
    final json = stored is Map ? stored : const {};
    final groups = <LibraryResultGroup>{};
    final order = json['groups'];
    if (order is List) {
      for (final key in order) {
        final group = LibraryResultGroup.values
            .where((group) => group.name == key)
            .firstOrNull;
        if (group != null) groups.add(group);
      }
    }
    groups.addAll(LibraryResultGroup.values);
    final hidden = json['hidden'];
    return LibrarySearchOptions(
      groups: groups.toList(),
      hidden: {
        if (hidden is List)
          for (final group in groups)
            if (hidden.contains(group.name)) group,
      },
      recentLimit: json['recentLimit'] is int
          ? (json['recentLimit'] as int).clamp(0, 100)
          : 0,
      ignoreArticles: json['ignoreArticles'] == true,
    );
  }

  final List<LibraryResultGroup> groups;
  final Set<LibraryResultGroup> hidden;
  final int recentLimit;
  final bool ignoreArticles;

  List<int> orderedResults(Map<LibraryResultGroup, int> sizes) {
    final starts = <LibraryResultGroup, int>{};
    var index = 0;
    for (final group in LibraryResultGroup.values) {
      starts[group] = index;
      index += sizes[group] ?? 0;
    }
    return [
      for (final group in groups)
        if (!hidden.contains(group))
          for (var offset = 0; offset < (sizes[group] ?? 0); offset++)
            starts[group]! + offset,
    ];
  }

  String titleKey(String title) {
    final folded = title.trim().toLowerCase();
    return ignoreArticles
        ? folded.replaceFirst(RegExp(r'^(the|an|a)\s+'), '')
        : folded;
  }

  Map<String, Object> toJson() => {
    'groups': groups.map((group) => group.name).toList(),
    'hidden': hidden.map((group) => group.name).toList(),
    'recentLimit': recentLimit,
    'ignoreArticles': ignoreArticles,
  };
}

Future<LibrarySearchOptions?> chooseSearchOptions(
  BuildContext context,
  LibrarySearchOptions current,
) {
  final groups = [...current.groups];
  final hidden = {...current.hidden};
  var recentLimit = current.recentLimit;
  var ignoreArticles = current.ignoreArticles;
  return showDialog<LibrarySearchOptions>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: const Text('Search and sorting'),
        scrollable: true,
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, group) in groups.indexed)
                ListTile(
                  leading: Checkbox(
                    value: !hidden.contains(group),
                    onChanged: (value) => refresh(
                      () => value == true
                          ? hidden.remove(group)
                          : hidden.add(group),
                    ),
                  ),
                  title: Text(group.label),
                  trailing: IconButton(
                    tooltip: 'Move earlier',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: index == 0
                        ? null
                        : () => refresh(() {
                            groups.removeAt(index);
                            groups.insert(index - 1, group);
                          }),
                  ),
                ),
              ListTile(
                title: const Text('Recent scores to show'),
                trailing: DropdownButton<int>(
                  value: recentLimit,
                  items: [
                    for (final count in {0, 10, 20, 50, 100, recentLimit})
                      DropdownMenuItem(
                        value: count,
                        child: Text(count == 0 ? 'All' : '$count'),
                      ),
                  ],
                  onChanged: (value) => refresh(() => recentLimit = value!),
                ),
              ),
              SwitchListTile(
                title: const Text('Ignore A, An and The in title order'),
                value: ignoreArticles,
                onChanged: (value) => refresh(() => ignoreArticles = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              LibrarySearchOptions(
                groups: groups,
                hidden: hidden,
                recentLimit: recentLimit,
                ignoreArticles: ignoreArticles,
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
