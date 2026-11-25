import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;

import 'score_library.dart';
import 'cloud_provider.dart';
import 'direct_cloud_screen.dart';
import 'app_document_paths.dart';

class CloudFilesScreen extends StatefulWidget {
  const CloudFilesScreen({super.key, required this.library});
  final ScoreLibrary library;

  @override
  State<CloudFilesScreen> createState() => _CloudFilesScreenState();
}

class _CloudFilesScreenState extends State<CloudFilesScreen> {
  static const _pdf = XTypeGroup(
    label: 'PDF scores',
    extensions: ['pdf'],
    mimeTypes: ['application/pdf'],
    uniformTypeIdentifiers: ['com.adobe.pdf'],
  );
  bool _busy = false;
  String? _status;
  String? _selection;
  ScoreEntry? _lastImported;
  bool get _appleFiles =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await task();
    } catch (_) {
      _status = 'Could not complete this file transfer.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() => _run(() async {
    final files = await openFiles(acceptedTypeGroups: const [_pdf]);
    var count = 0;
    var failed = 0;
    for (final file in files) {
      if (!mounted) return;
      try {
        final (score, _) = await widget.library.import(file);
        _lastImported = score;
        count++;
      } catch (_) {
        failed++;
      }
    }
    if (files.isNotEmpty)
      _status =
          'Imported $count scores.${failed == 0 ? '' : ' $failed could not be copied.'}';
  });

  Future<void> _openProvider(DirectCloudProvider provider) => _run(() async {
    final score = await Navigator.of(context).push<ScoreEntry>(
      MaterialPageRoute(
        builder: (_) =>
            DirectCloudScreen(provider: provider, library: widget.library),
      ),
    );
    if (score != null && mounted) Navigator.pop(context, score);
  });

  Future<void> _export() => _run(() async {
    final score = _selection == null
        ? null
        : widget.library.lookup(_selection!);
    if (score == null) return;
    final box = context.findRenderObject() as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final name =
        '${score.title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')}.pdf';
    final scoreFile = await widget.library.storage.openScore(score.id);
    if (!mounted) return;
    if (!kIsWeb &&
        const {
          TargetPlatform.windows,
          TargetPlatform.linux,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform)) {
      final destination = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [_pdf],
      );
      if (destination == null) return;
      await scoreFile.saveTo(destination.path);
      _status = 'Score saved.';
    } else {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              await scoreFile.readAsBytes(),
              mimeType: 'application/pdf',
              name: name,
            ),
          ],
          fileNameOverrides: [name],
          sharePositionOrigin: anchor,
        ),
      );
    }
  });

  Future<void> _importTransferFile() => _run(() async {
    final files = await transferScores();
    if (!mounted) return;
    if (files.isEmpty) {
      _status = 'Copy a PDF into On My iPad or On My iPhone → EncoreSheets → Scores for Transfer.';
      return;
    }
    final file = await showDialog<XFile>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Scores for Transfer'),
        children: [
          for (final file in files)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, file),
              child: Text(file.name),
            ),
        ],
      ),
    );
    if (file == null || !mounted) return;
    final (score, _) = await widget.library.import(file);
    _lastImported = score;
    _status = 'Imported ${score.title}.';
  });

  Future<void> _exportTransferFile() => _run(() async {
    final id = _selection;
    final score = id == null ? null : widget.library.lookup(id);
    if (score == null) return;
    final title = score.title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    final name = await saveTransferScore(
      await widget.library.storage.openScore(score.id),
      '${title.isEmpty ? 'Score' : title}.pdf',
    );
    _status = 'Saved $name in EncoreSheets → Scores for Transfer.';
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Cloud files')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Use the file picker to browse services connected to your device. On a tablet, choose a storage provider from the share sheet when saving a PDF.',
            ),
            for (final provider in DirectCloudProvider.values)
              TextButton(
                onPressed: _busy ? null : () => _openProvider(provider),
                child: Text('Browse ${provider.label} directly'),
              ),
            FilledButton(
              onPressed: _busy ? null : _import,
              child: const Text('Browse and import PDFs'),
            ),
            if (_appleFiles)
              TextButton(
                onPressed: _busy ? null : _importTransferFile,
                child: const Text('Import from Scores for Transfer'),
              ),
            if (_lastImported case final score?)
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, score),
                child: const Text('Open last imported score'),
              ),
            const Divider(),
            DropdownButton<String>(
              isExpanded: true,
              value: _selection,
              hint: const Text('Choose a score to save'),
              items: [
                for (final score in widget.library.recent)
                  DropdownMenuItem(
                    value: score.id,
                    child: Text(score.title, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _selection = value),
            ),
            TextButton(
              onPressed: _busy || _selection == null ? null : _export,
              child: const Text('Save or share PDF'),
            ),
            if (_appleFiles)
              TextButton(
                onPressed: _busy || _selection == null
                    ? null
                    : _exportTransferFile,
                child: const Text('Copy to EncoreSheets in Files'),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_status case final status?) Text(status),
          ],
        ),
      ),
    ),
  );
}
