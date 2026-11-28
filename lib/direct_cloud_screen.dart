import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const _oneDriveClientId = String.fromEnvironment(
    'ENCORE_ONEDRIVE_CLIENT_ID',
  );
  static final _oneDriveDeviceCode = Uri.https(
    'login.microsoftonline.com',
    '/common/oauth2/v2.0/devicecode',
  );
  static final _oneDriveToken = Uri.https(
    'login.microsoftonline.com',
    '/common/oauth2/v2.0/token',
  );
  bool get _canSignIn =>
      widget.provider == DirectCloudProvider.oneDrive &&
      _oneDriveClientId.isNotEmpty;

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
      if (error is CloudTransferError && error.needsRenewal) {
        _session?.close();
        _session = null;
        _items = [];
        _path.removeRange(1, _path.length);
      }
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
    await _connectToken(token);
  });

  Future<void> _connectToken(String token) async {
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
  }

  Future<void> _signIn() => _run(() async {
    final client = http.Client();
    try {
      final response = await client
          .post(
            _oneDriveDeviceCode,
            body: {
              'client_id': _oneDriveClientId,
              'scope': 'https://graph.microsoft.com/Files.ReadWrite',
            },
          )
          .timeout(const Duration(seconds: 15));
      final code = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          code is! Map<String, dynamic> ||
          code['device_code'] is! String ||
          code['user_code'] is! String ||
          code['expires_in'] is! int) {
        throw const CloudTransferError(
          'OneDrive could not start sign-in. Try again.',
        );
      }
      if (!mounted) return;
      final expiry = DateTime.now().add(
        Duration(seconds: code['expires_in'] as int),
      );
      var interval = code['interval'] is int ? code['interval'] as int : 5;
      final token = await showDialog<String>(
        context: context,
        builder: (dialog) {
          return AlertDialog(
            title: const Text('Sign in to OneDrive'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter this code on the Microsoft sign-in page.'),
                SelectableText(code['user_code'] as String),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: code['user_code'] as String),
                    );
                    await launchUrl(
                      Uri.https('microsoft.com', '/devicelogin'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: const Text('Copy code and open Microsoft'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialog, code['device_code'] as String),
                child: const Text('I signed in'),
              ),
            ],
          );
        },
      );
      if (token == null || !mounted) return;
      while (mounted && DateTime.now().isBefore(expiry)) {
        await Future<void>.delayed(
          Duration(seconds: interval.clamp(1, 60).toInt()),
        );
        if (!mounted) return;
        final result = await client
            .post(
              _oneDriveToken,
              body: {
                'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
                'client_id': _oneDriveClientId,
                'device_code': token,
              },
            )
            .timeout(const Duration(seconds: 15));
        final data = jsonDecode(result.body);
        if (data is Map<String, dynamic>) {
          if (data['access_token'] case final String access
              when access.isNotEmpty) {
            await _connectToken(access);
            return;
          }
          if (data['error'] == 'authorization_pending') continue;
          if (data['error'] == 'slow_down') {
            interval += 5;
            continue;
          }
        }
        break;
      }
      if (mounted)
        throw const CloudTransferError(
          'OneDrive sign-in ended. Start again to reconnect.',
        );
    } finally {
      client.close();
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
            if (_session == null && _canSignIn)
              FilledButton(
                onPressed: _busy ? null : _signIn,
                child: const Text('Sign in to OneDrive'),
              )
            else if (_session == null) ...[
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
