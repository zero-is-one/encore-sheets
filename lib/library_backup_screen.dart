import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'score_library.dart';

class LibraryBackupScreen extends StatefulWidget {
  const LibraryBackupScreen({
    super.key,
    required this.library,
    this.recoveryRequired = false,
  });

  final ScoreLibrary library;
  final bool recoveryRequired;

  @override
  State<LibraryBackupScreen> createState() => _LibraryBackupScreenState();
}

class _LibraryBackupScreenState extends State<LibraryBackupScreen> {
  static const _zip = XTypeGroup(
    label: 'EncoreSheets backups',
    extensions: ['zip'],
    mimeTypes: ['application/zip'],
    uniformTypeIdentifiers: ['public.zip-archive'],
  );

  String? _operation;
  String? _message;

  Future<void> _chooseBackupType() async {
    final includeScores = await showDialog<bool>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Create backup'),
        children: [
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Full backup'),
            subtitle: const Text(
              'Includes score PDFs and library data. Restoring adds copies to your library.',
            ),
            onTap: () => Navigator.pop(dialog, true),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Metadata-only backup'),
            subtitle: const Text(
              'Updates matching scores on restore. Keep your PDFs separately.',
            ),
            onTap: () => Navigator.pop(dialog, false),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Text(
              'Keep separate copies of linked audio and practice recordings.',
            ),
          ),
        ],
      ),
    );
    if (!mounted || includeScores == null) return;
    await _run('Create backup', () => _export(includeScores: includeScores));
  }

  Future<void> _run(String operation, Future<String?> Function() work) async {
    if (_operation != null) return;
    setState(() {
      _operation = operation;
      _message = null;
    });
    try {
      final message = await work();
      if (mounted) setState(() => _message = message);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not ${operation.toLowerCase()}.');
      }
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _restoreScoreVersion(ScoreEntry version, bool replace) async {
    if (replace) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('Replace ${version.title}?'),
          content: const Text(
            'The current version will still be available under Recently updated.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _run('Restore score version', () async {
      final restored = await widget.library.restoreScoreVersion(
        version.id,
        replace: replace,
      );
      return 'Restored ${restored.title}.';
    });
  }

  Future<String?> _export({bool includeScores = true}) async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final zip = await widget.library.createBackup(includeScores: includeScores);
    if (!mounted) return null;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final saved = await const MethodChannel('encoresheets/backup')
          .invokeMethod<bool>('save', {'path': zip.path});
      return saved == true ? 'Backup saved.' : null;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final result = await SharePlus.instance.share(
        ShareParams(files: [zip], sharePositionOrigin: origin),
      );
      return result.status == ShareResultStatus.success
          ? 'Backup exported.'
          : null;
    }
    final location = await getSaveLocation(
      suggestedName: zip.name,
      acceptedTypeGroups: [_zip],
    );
    if (location == null) return null;
    await zip.saveTo(location.path);
    return 'Backup saved.';
  }

  Future<String?> _restore() async {
    final source = await openFile(acceptedTypeGroups: const [_zip]);
    if (source == null || !mounted) return null;
    return _restoreFrom(source, 'Restore backup?');
  }

  Future<String?> _recoverSnapshot() async {
    final snapshot = await widget.library.storage.latestBackup();
    if (!mounted) return null;
    if (snapshot == null)
      return 'Create a backup to save a local recovery snapshot.';
    return _restoreFrom(snapshot, 'Restore latest local backup?');
  }

  Future<String?> _restoreFrom(XFile source, String title) async {
    var restoreSettings = true;
    final restore = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Full backups add copies. Metadata-only backups update matching scores.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Restore app settings'),
                value: restoreSettings,
                onChanged: (value) =>
                    setDialogState(() => restoreSettings = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      ),
    );
    if (restore != true || !mounted) return null;
    final restored = await widget.library.restoreBackup(
      source,
      restoreSettings: restoreSettings,
    );
    if (widget.recoveryRequired && mounted) {
      Navigator.pop(context, true);
      return null;
    }
    return 'Restored ${restored.scores} scores and ${restored.setlists} setlists.';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _operation == null,
    child: Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.recoveryRequired)
              const Text(
                'The library catalog could not be recovered automatically. Restore a full library backup to continue.',
              ),
            if (!widget.recoveryRequired) ...[
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              ExpansionTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Recently deleted'),
                subtitle: Text(
                  '${widget.library.recentlyDeleted.length} scores',
                ),
                children: [
                  if (widget.library.recentlyDeleted.isEmpty)
                    const ListTile(title: Text('No deleted scores.')),
                  for (final score in widget.library.recentlyDeleted)
                    ListTile(
                      title: Text(score.title),
                      trailing: TextButton(
                        onPressed: _operation != null
                            ? null
                            : () => _run('Recover score', () async {
                                await widget.library.recoverScore(score.id);
                                return 'Recovered ${score.title}.';
                              }),
                        child: const Text('Recover'),
                      ),
                    ),
                ],
              ),
              ExpansionTile(
                leading: const Icon(Icons.history),
                title: const Text('Recently updated'),
                subtitle: Text(
                  '${widget.library.recentlyUpdated.length} previous versions',
                ),
                children: [
                  if (widget.library.recentlyUpdated.isEmpty)
                    const ListTile(title: Text('No previous versions.')),
                  for (final version in widget.library.recentlyUpdated)
                    ListTile(
                      title: Text(version.title),
                      subtitle: Text(
                        MaterialLocalizations.of(context)
                            .formatMediumDate(version.deletedAt!.toLocal()),
                      ),
                      trailing: PopupMenuButton<bool>(
                        tooltip: 'Restore version of ${version.title}',
                        enabled: _operation == null,
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: false,
                            child: Text('Restore as a copy'),
                          ),
                          if (widget.library.replacementFor(version) != null)
                            const PopupMenuItem(
                              value: true,
                              child: Text('Replace edited score…'),
                            ),
                        ],
                        onSelected: (replace) =>
                            _restoreScoreVersion(version, replace),
                      ),
                    ),
                ],
              ),
              const Divider(),
            ],
            Text('Backups', style: Theme.of(context).textTheme.titleMedium),
            if (!widget.recoveryRequired && widget.library.storage.persistent)
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Create backup'),
                subtitle: const Text('Full or metadata-only'),
                enabled: _operation == null,
                onTap: _operation == null ? _chooseBackupType : null,
              ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('Restore from a file'),
              enabled: _operation == null && widget.library.storage.persistent,
              onTap: _operation == null && widget.library.storage.persistent
                  ? () => _run('Restore backup', _restore)
                  : null,
            ),
            if (widget.library.storage.persistent)
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Restore latest local backup'),
                enabled: _operation == null,
                onTap: _operation == null
                    ? () =>
                          _run('Restore latest local backup', _recoverSnapshot)
                    : null,
              ),
            if (_operation != null) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_message case final message?) ...[
              const SizedBox(height: 16),
              Semantics(liveRegion: true, child: Text(message)),
            ],
          ],
        ),
      ),
    ),
  );
}
