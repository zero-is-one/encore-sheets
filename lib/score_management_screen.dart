import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_assembly_screen.dart';
import 'score_library.dart';
import 'score_metadata_screen.dart';

class ScoreManagementScreen extends StatefulWidget {
  const ScoreManagementScreen({super.key, required this.library});

  final ScoreLibrary library;

  @override
  State<ScoreManagementScreen> createState() => _ScoreManagementScreenState();
}

class _ScoreManagementScreenState extends State<ScoreManagementScreen> {
  final _ids = <String>{};
  bool _busy = false;

  List<ScoreEntry> get _selected =>
      _ids.map(widget.library.lookup).whereType<ScoreEntry>().toList();

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not complete the score action.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() => _run(() async {
    final edit = await editBatchMetadata(context, _selected, selectAll: true);
    if (edit == null) return;
    await widget.library.batchMetadata(
      edit.ids,
      edit.field,
      edit.value,
      append: edit.append,
    );
  });

  Future<void> _share() => _run(() async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final files = <XFile>[];
    final names = <String>[];
    for (final score in _selected) {
      files.add(await widget.library.storage.openScore(score.id));
      final title = score.title.replaceAll(
        RegExp(r'[<>:"/\\|?*\x00-\x1f]'),
        '_',
      );
      final stem = title.isEmpty ? 'Score' : title;
      var name = '$stem.pdf';
      var suffix = 2;
      while (names.any((other) => other.toLowerCase() == name.toLowerCase())) {
        name = '$stem (${suffix++}).pdf';
      }
      names.add(name);
    }
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        fileNameOverrides: names,
        sharePositionOrigin: origin,
      ),
    );
  });

  Future<void> _combine() => _run(() async {
    final score = await Navigator.of(context).push<ScoreEntry>(
      MaterialPageRoute(
        builder: (_) => PdfAssemblyScreen(
          library: widget.library,
          initialSelection: _selected,
        ),
      ),
    );
    if (score != null && mounted) Navigator.pop(context, score);
  });

  Future<void> _delete() => _run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete ${_ids.length} selected scores?'),
        content: const Text(
          'You can recover deleted scores from Backup & restore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Move to Recently deleted'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.library.trashScores(_ids);
    if (mounted) setState(_ids.clear);
  });

  @override
  Widget build(BuildContext context) {
    final scores = widget.library.recent;
    final enabled = !_busy && _ids.isNotEmpty;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text('${_ids.length} selected')),
        body: SafeArea(
          child: Column(
            children: [
              Wrap(
                children: [
                  TextButton(
                    onPressed: enabled ? _edit : null,
                    child: const Text('Edit metadata'),
                  ),
                  TextButton(
                    onPressed: enabled ? _share : null,
                    child: const Text('Share PDFs'),
                  ),
                  TextButton(
                    onPressed: enabled && _ids.length > 1 ? _combine : null,
                    child: const Text('Combine'),
                  ),
                  TextButton(
                    onPressed: enabled ? _delete : null,
                    child: const Text('Delete'),
                  ),
                ],
              ),
              if (_busy) const LinearProgressIndicator(),
              Expanded(
                child: ListView.builder(
                  itemCount: scores.length,
                  itemBuilder: (_, index) {
                    final score = scores[index];
                    return CheckboxListTile(
                      title: Text(score.title),
                      value: _ids.contains(score.id),
                      onChanged: _busy
                          ? null
                          : (checked) => setState(() {
                              if (checked == true) {
                                _ids.add(score.id);
                              } else {
                                _ids.remove(score.id);
                              }
                            }),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
