import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'score_action.dart';
import 'score_library.dart';

class ScoreActionsScreen extends StatefulWidget {
  const ScoreActionsScreen({
    super.key,
    required this.document,
    required this.page,
    required this.library,
    required this.actions,
  });

  final PdfDocument document;
  final int page;
  final ScoreLibrary library;
  final List<ScoreAction> actions;

  @override
  State<ScoreActionsScreen> createState() => _ScoreActionsScreenState();
}

class _ScoreActionsScreenState extends State<ScoreActionsScreen> {
  static const _colors = {
    0xff254a73: 'Blue',
    0xff86532b: 'Amber',
    0xff336344: 'Green',
    0xff943d49: 'Red',
  };

  late final _actions = [...widget.actions];

  Future<void> _edit([ScoreAction? current]) async {
    var title = current?.title ?? '';
    var kind = current?.kind ?? ScoreActionKind.note;
    var color = current?.color ?? _colors.keys.first;
    var x = current?.x ?? .5;
    var y = current?.y ?? .25;
    var selection = current?.selection;
    final choices = {
      for (final score in widget.library.recent) ...{
        score.id: score.title,
        for (final item in score.bookmarks)
          if (item.isItem)
            item.selectionId(score.id): '${score.title} · ${item.title}',
      },
    };
    final result = await showDialog<ScoreAction>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, refresh) => AlertDialog(
          title: Text(
            current == null ? 'Add action button' : 'Edit action button',
          ),
          scrollable: true,
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: title,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Button label'),
                  onChanged: (value) => refresh(() => title = value),
                ),
                DropdownButton<ScoreActionKind>(
                  isExpanded: true,
                  value: kind,
                  items: [
                    for (final item in ScoreActionKind.values)
                      DropdownMenuItem(value: item, child: Text(item.label)),
                  ],
                  onChanged: (value) => refresh(() => kind = value!),
                ),
                if (kind == ScoreActionKind.score)
                  DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('Destination score'),
                    value: choices.containsKey(selection) ? selection : null,
                    items: [
                      for (final choice in choices.entries)
                        DropdownMenuItem(
                          value: choice.key,
                          child: Text(
                            choice.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => refresh(() => selection = value),
                  ),
                DropdownButton<int>(
                  isExpanded: true,
                  value: _colors.containsKey(color)
                      ? color
                      : _colors.keys.first,
                  items: [
                    for (final swatch in _colors.entries)
                      DropdownMenuItem(
                        value: swatch.key,
                        child: Text(swatch.value),
                      ),
                  ],
                  onChanged: (value) => refresh(() => color = value!),
                ),
                SizedBox(
                  height: 175,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio:
                          widget.document.pages[widget.page - 1].width /
                          widget.document.pages[widget.page - 1].height,
                      child: LayoutBuilder(
                        builder: (context, bounds) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (event) => refresh(() {
                            x = (event.localPosition.dx / bounds.maxWidth)
                                .clamp(0.0, 1.0);
                            y = (event.localPosition.dy / bounds.maxHeight)
                                .clamp(0.0, 1.0);
                          }),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PdfPageView(
                                document: widget.document,
                                pageNumber: widget.page,
                                maximumDpi: 70,
                              ),
                              Align(
                                alignment: Alignment(2 * x - 1, 2 * y - 1),
                                child: Icon(
                                  Icons.circle,
                                  size: 16,
                                  color: Color(color),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Text('Tap the preview to place the button.'),
                Slider(
                  value: x,
                  onChanged: (value) => refresh(() => x = value),
                  semanticFormatterCallback: (value) =>
                      'Horizontal position ${(value * 100).round()} percent',
                ),
                Slider(
                  value: y,
                  onChanged: (value) => refresh(() => y = value),
                  semanticFormatterCallback: (value) =>
                      'Vertical position ${(value * 100).round()} percent',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  title.trim().isEmpty ||
                      kind == ScoreActionKind.score &&
                          !choices.containsKey(selection)
                  ? null
                  : () => Navigator.pop(
                      dialog,
                      ScoreAction(
                        title: title.trim(),
                        page: widget.page,
                        x: x,
                        y: y,
                        color: color,
                        kind: kind,
                        selection: kind == ScoreActionKind.score
                            ? selection
                            : null,
                      ),
                    ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (current == null) {
        _actions.add(result);
      } else {
        _actions[_actions.indexOf(current)] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Page ${widget.page} actions'),
      actions: [
        IconButton(
          onPressed: _edit,
          icon: const Icon(Icons.add),
          tooltip: 'Add action button',
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _actions),
          child: const Text('Done'),
        ),
      ],
    ),
    body: ListView(
      children: [
        for (final action in _actions)
          if (action.page == widget.page)
            ListTile(
              leading: Icon(Icons.circle, color: Color(action.color)),
              title: Text(action.title),
              subtitle: Text(action.kind.label),
              onTap: () => _edit(action),
              trailing: IconButton(
                tooltip: 'Remove ${action.title}',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => _actions.remove(action)),
              ),
            ),
      ],
    ),
  );
}
