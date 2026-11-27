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
            Text(
              widget.recoveryRequired
                  ? 'The library catalog could not be recovered automatically. Restore a full library backup to open the library again.'
                  : 'A backup includes your PDFs, annotations, setlists, libraries, and reader settings. Keep separate copies of linked audio and practice recordings. EncoreSheets keeps two local catalog snapshots for automatic recovery.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  !widget.recoveryRequired &&
                      _operation == null &&
                      widget.library.storage.persistent
                  ? () => _run('Create backup', _export)
                  : null,
              icon: const Icon(Icons.save_alt),
              label: const Text('Create full backup'),
            ),
            const Text(
              'Includes score PDFs and library data. Restoring adds copies to your library.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _operation == null && widget.library.storage.persistent
                  ? () => _run('Restore backup', _restore)
                  : null,
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('Restore backup'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  !widget.recoveryRequired &&
                      _operation == null &&
                      widget.library.storage.persistent
                  ? () => _run(
                      'Create metadata backup',
                      () => _export(includeScores: false),
                    )
                  : null,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Create metadata-only backup'),
            ),
            const Text(
              'Excludes score PDFs. Restoring updates metadata on matching scores.',
            ),
            if (widget.library.storage.persistent)
              TextButton.icon(
                onPressed: _operation == null
                    ? () =>
                          _run('Restore latest local backup', _recoverSnapshot)
                    : null,
                icon: const Icon(Icons.history),
                label: const Text('Restore latest local backup'),
              ),
            const SizedBox(height: 24),
            Text(
              'Recently deleted',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (widget.library.recentlyDeleted.isEmpty)
              const Text('No deleted scores.'),
            for (final score in widget.library.recentlyDeleted)
              ListTile(
                contentPadding: EdgeInsets.zero,
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
