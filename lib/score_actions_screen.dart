import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'score_action.dart';
import 'score_action_destination.dart';
import 'pitch_detection.dart';
import 'score_library.dart';

class ScoreActionsScreen extends StatefulWidget {
  const ScoreActionsScreen({
    super.key,
    required this.document,
    required this.page,
    required this.library,
    required this.actions,
    required this.allowFiles,
  });

  final PdfDocument document;
  final int page;
  final ScoreLibrary library;
  final List<ScoreAction> actions;
  final bool allowFiles;

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
  bool _savingAttachment = false;

  Future<void> _edit([ScoreAction? current]) async {
    if (_savingAttachment) return;
    var title = current?.title ?? '';
    var showLabel = current?.showLabel ?? false;
    var kind = current?.kind ?? ScoreActionKind.note;
    var color = current?.color ?? _colors.keys.first;
    var x = current?.x ?? .5;
    var y = current?.y ?? .25;
    var selection = current?.selection;
    var parameter = current?.parameter ?? '';
    XFile? attachment;
    final choices = {
      for (final score in widget.library.recent) ...{
        score.id: score.title,
        for (final item in score.bookmarks)
          if (item.isItem)
            item.selectionId(score.id): '${score.title} · ${item.title}',
      },
    };
    final result = await showDialog<(ScoreAction, XFile?)>(
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show label on score'),
                  value: showLabel,
                  onChanged: (value) => refresh(() => showLabel = value),
                ),
                DropdownButton<ScoreActionKind>(
                  isExpanded: true,
                  value: kind,
                  items: [
                    for (final item in ScoreActionKind.values)
                      if (item == current?.kind ||
                          (item != ScoreActionKind.externalApp || !kIsWeb) &&
                              (item != ScoreActionKind.externalFile ||
                                  widget.allowFiles &&
                                      supportsExternalScoreFiles))
                        DropdownMenuItem(value: item, child: Text(item.label)),
                  ],
                  onChanged: (value) => refresh(() {
                    kind = value!;
                    parameter = switch (kind) {
                      _ when kind == current?.kind => current?.parameter ?? '',
                      ScoreActionKind.tempo => '96',
                      ScoreActionKind.pitch => '69',
                      _ => '',
                    };
                  }),
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
                if (kind == ScoreActionKind.pitch)
                  DropdownButton<int>(
                    value: int.tryParse(parameter) ?? 69,
                    items: [
                      for (var note = 48; note <= 84; note++)
                        DropdownMenuItem(
                          value: note,
                          child: Text(noteLabel(note)),
                        ),
                    ],
                    onChanged: (value) => refresh(() => parameter = '$value'),
                  ),
                if (kind == ScoreActionKind.tempo ||
                    kind == ScoreActionKind.midi)
                  TextFormField(
                    key: ValueKey(kind),
                    initialValue: parameter,
                    keyboardType: kind == ScoreActionKind.tempo
                        ? TextInputType.number
                        : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: kind == ScoreActionKind.tempo
                          ? 'Tempo (BPM)'
                          : 'MIDI message (hex)',
                      hintText: kind == ScoreActionKind.tempo
                          ? '25–280'
                          : 'Example: C0 05',
                    ),
                    onChanged: (value) =>
                        refresh(() => parameter = value.trim()),
                  ),
                if (kind == ScoreActionKind.website ||
                    kind == ScoreActionKind.externalApp)
                  TextFormField(
                    key: ValueKey(kind),
                    initialValue: parameter,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: kind == ScoreActionKind.website
                          ? 'Website URL'
                          : 'App link',
                      hintText: kind == ScoreActionKind.website
                          ? 'https://example.com'
                          : 'HTTPS app link or spotify:…',
                      helperText: kind == ScoreActionKind.externalApp
                          ? 'Also supports YouTube, Music, Maps, and VLC links.'
                          : null,
                    ),
                    onChanged: (value) =>
                        refresh(() => parameter = value.trim()),
                  ),
                if (kind == ScoreActionKind.externalFile)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      attachment?.name ??
                          ScoreAction.fileReference(parameter)?.name ??
                          'Choose a file',
                    ),
                    onPressed: !widget.allowFiles || !supportsExternalScoreFiles
                        ? null
                        : () async {
                            try {
                              final selected = await openFile(
                                acceptedTypeGroups: [
                                  XTypeGroup(
                                    label: 'Documents, images, and audio',
                                    extensions: ScoreAction.fileExtensions
                                        .toList(),
                                    mimeTypes: const [
                                      'application/pdf',
                                      'text/plain',
                                      'application/rtf',
                                      'application/msword',
                                      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                                      'image/png',
                                      'image/jpeg',
                                      'audio/*',
                                    ],
                                    uniformTypeIdentifiers: const [
                                      'public.content',
                                      'public.audio',
                                    ],
                                  ),
                                ],
                              );
                              if (dialog.mounted && selected != null) {
                                refresh(() => attachment = selected);
                              }
                            } catch (_) {
                              if (dialog.mounted)
                                ScaffoldMessenger.of(dialog).showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not choose a file.'),
                                  ),
                                );
                            }
                          },
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
                      !(kind == ScoreActionKind.externalFile &&
                              attachment != null ||
                          ScoreAction.validParameter(kind, parameter)) ||
                      kind == ScoreActionKind.score &&
                          !choices.containsKey(selection)
                  ? null
                  : () => Navigator.pop(dialog, (
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
                        parameter: parameter.isEmpty ? null : parameter,
                        showLabel: showLabel,
                      ),
                      kind == ScoreActionKind.externalFile ? attachment : null,
                    )),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    var (action, file) = result;
    if (file != null) {
      setState(() => _savingAttachment = true);
      try {
        action = action.withParameter(await storeScoreActionFile(file));
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not save that file. Choose a supported document, image, or audio file.',
              ),
            ),
          );
        return;
      } finally {
        if (mounted) setState(() => _savingAttachment = false);
      }
    }
    if (!mounted) return;
    setState(() {
      if (current == null) {
        _actions.add(action);
      } else {
        _actions[_actions.indexOf(current)] = action;
      }
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_savingAttachment,
    child: Scaffold(
      appBar: AppBar(
        title: Text('Page ${widget.page} actions'),
        actions: [
          IconButton(
            onPressed: _savingAttachment ? null : _edit,
            icon: const Icon(Icons.add),
            tooltip: 'Add action button',
          ),
          TextButton(
            onPressed: _savingAttachment
                ? null
                : () => Navigator.pop(context, _actions),
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
                  onPressed: _savingAttachment
                      ? null
                      : () => setState(() => _actions.remove(action)),
                ),
              ),
        ],
      ),
    ),
  );
}
