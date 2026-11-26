import 'package:material_ui/material_ui.dart';

import 'cloud_provider.dart';
import 'score_library.dart';
import 'score_clipboard.dart';

class DirectCloudScreen extends StatefulWidget {
  const DirectCloudScreen({
    super.key,
    required this.provider,
    required this.library,
  });
  final DirectCloudProvider provider;
  final ScoreLibrary library;

  @override
  State<DirectCloudScreen> createState() => _DirectCloudScreenState();
}

class _DirectCloudScreenState extends State<DirectCloudScreen> {
  final _token = TextEditingController();
  late final _path = <CloudItem>[
    (id: widget.provider.root, name: widget.provider.label, folder: true),
  ];
  CloudProviderSession? _session;
  List<CloudItem> _items = [];
  bool _busy = false;
  String? _status;
  ScoreEntry? _latest;

  @override
  void dispose() {
    _token.dispose();
    _session?.close();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await operation();
    } catch (error) {
      _status = error is CloudTransferError
          ? error.message
          : 'Could not complete the cloud transfer.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
    final token = _token.text.trim();
    if (token.isEmpty)
      throw const CloudTransferError('Enter a provider access token.');
    final session = CloudProviderSession(widget.provider, token);
    try {
      final items = await session.folder(widget.provider.root);
      if (!mounted) {
        session.close();
        return;
      }
      _token.clear();
      _session = session;
      _items = items;
    } catch (_) {
      session.close();
      rethrow;
    }
  });

  Future<void> _open(CloudItem item) => _run(() async {
    if (item.folder) {
      final next = await _session!.folder(item.id);
      _path.add(item);
      _items = next;
      return;
    }
    final file = await _session!.download(item);
    if (!mounted) return;
    final (score, _) = await widget.library.import(file);
    _latest = score;
    _status = 'Imported ${score.title}.';
  });

  Future<void> _up() => _run(() async {
    final next = await _session!.folder(_path[_path.length - 2].id);
    _path.removeLast();
    _items = next;
  });

  Future<void> _upload() => _run(() async {
    final score = await showDialog<ScoreEntry>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text('Upload a score to ${_path.last.name}'),
        children: [
          for (final score in widget.library.recent)
            if (score.validUntil == null)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, score),
                child: Text(score.title),
              ),
        ],
      ),
    );
    if (score == null || !mounted) return;
    final stem = score.title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim();
    var name = '${stem.isEmpty ? 'Score' : stem}.pdf';
    if (!widget.provider.supportsClipboard) {
      var filename = name;
      final chosen = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Upload PDF'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: name,
                decoration: const InputDecoration(labelText: 'Filename'),
                onChanged: (value) => filename = value.trim(),
              ),
              Text(
                widget.provider == DirectCloudProvider.googleDrive
                    ? 'Google Drive keeps files with the same name as separate copies.'
                    : 'If this name is taken, choose a different filename.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, filename),
              child: const Text('Upload'),
            ),
          ],
        ),
      );
      if (chosen == null || !mounted) return;
      if (chosen.isEmpty || chosen.contains(RegExp(r'[<>:"/\\|?*\x00-\x1f]'))) {
        throw const CloudTransferError('Choose a valid PDF filename.');
      }
      name = chosen.toLowerCase().endsWith('.pdf') ? chosen : '$chosen.pdf';
    }
    await _session!.upload(
      _path.last.id,
      name,
      await widget.library.storage.openScore(score.id),
    );
    _items = await _session!.folder(_path.last.id);
    _status = 'Uploaded $name.';
  });

  Future<void> _copyFile(CloudItem item, {required bool move}) =>
      _run(() async {
        await writeScoreClipboard((
          scope: widget.provider.name,
          id: item.id,
          name: item.name,
          move: move,
        ));
        _status = move
            ? 'Choose a folder and paste to move this PDF.'
            : 'PDF copied.';
      });

  Future<void> _pasteFile() => _run(() async {
    final item = await readScoreClipboard();
    if (item == null || item.scope != widget.provider.name) {
      throw CloudTransferError(
        'Copy or cut a PDF from ${widget.provider.label} first.',
      );
    }
    await _session!.transfer(
      sourceId: item.id,
      filename: item.name,
      folderId: _path.last.id,
      move: item.move,
    );
    try {
      await clearMovedScoreClipboard(item);
    } catch (_) {
      // The remote transfer has already completed.
    }
    _items = await _session!.folder(_path.last.id);
    _status = item.move ? 'Moved ${item.name}.' : 'Copied ${item.name}.';
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.provider.label)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_status case final status?) Text(status),
            if (_session == null) ...[
              Text(switch (widget.provider) {
                DirectCloudProvider.googleDrive => 'Use a Google Drive access token with the Drive read/write scope.',
                DirectCloudProvider.oneDrive => 'Use a Microsoft Graph access token with delegated Files.ReadWrite permission.',
                _ => 'Use a provider access token with file access.',
              }),
              const Text('The token is cleared when you close this screen.'),
              TextField(
                controller: _token,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Access token'),
                onSubmitted: (_) => _connect(),
              ),
              FilledButton(
                onPressed: _busy ? null : _connect,
                child: const Text('Connect'),
              ),
            ] else ...[
              Text(_path.map((entry) => entry.name).join(' / ')),
              Wrap(
                spacing: 8,
                children: [
                  if (_path.length > 1)
                    TextButton(
                      onPressed: _busy ? null : _up,
                      child: const Text('Parent folder'),
                    ),
                  TextButton(
                    onPressed:
                        _busy ||
                            !widget.library.recent.any(
                              (score) => score.validUntil == null,
                            )
                        ? null
                        : _upload,
                    child: const Text('Upload score'),
                  ),
                  if (widget.provider.supportsClipboard)
                    TextButton(
                      onPressed: _busy ? null : _pasteFile,
                      child: const Text('Paste PDF'),
                    ),
                  if (_latest case final score?)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, score),
                      child: const Text('Open last imported'),
                    ),
                ],
              ),
              for (final item in _items)
                ListTile(
                  leading: Icon(
                    item.folder
                        ? Icons.folder_outlined
                        : Icons.picture_as_pdf_outlined,
                  ),
                  title: Text(item.name),
                  trailing: item.folder
                      ? const Icon(Icons.chevron_right)
                      : !widget.provider.supportsClipboard
                      ? const Icon(Icons.download_outlined)
                      : PopupMenuButton<bool>(
                          enabled: !_busy,
                          tooltip: 'PDF clipboard actions',
                          onSelected: (move) => _copyFile(item, move: move),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: false,
                              child: Text('Copy PDF'),
                            ),
                            PopupMenuItem(value: true, child: Text('Cut PDF')),
                          ],
                        ),
                  onTap: _busy ? null : () => _open(item),
                ),
              if (_items.isEmpty && !_busy)
                const Text('No folders or PDFs in this location.'),
            ],
          ],
        ),
      ),
    ),
  );
}
