import 'package:material_ui/material_ui.dart';

enum QuickReaderTool {
  library('Recent scores', Icons.history),
  bookmarks('Bookmarks', Icons.bookmark_outline),
  layers('Annotation layers', Icons.layers_outlined),
  presets('Drawing presets', Icons.draw_outlined),
  metronome('Metronome', Icons.timer_outlined),
  fit('Fit page', Icons.fit_screen);

  const QuickReaderTool(this.label, this.icon);
  final String label;
  final IconData icon;
}

Set<QuickReaderTool> readQuickReaderTools(Object? saved) => saved is List
    ? QuickReaderTool.values.where((tool) => saved.contains(tool.name)).toSet()
    : QuickReaderTool.values.toSet();

Future<Set<QuickReaderTool>?> chooseQuickReaderTools(
  BuildContext context,
  Set<QuickReaderTool> original,
) {
  final draft = {...original};
  return showDialog<Set<QuickReaderTool>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        scrollable: true,
        title: const Text('Pin quick-access tools'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tool in QuickReaderTool.values)
              CheckboxListTile(
                title: Text(tool.label),
                value: draft.contains(tool),
                onChanged: (value) => refresh(() {
                  if (value == true) {
                    draft.add(tool);
                  } else {
                    draft.remove(tool);
                  }
                }),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
