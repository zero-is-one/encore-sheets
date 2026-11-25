import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'score_library.dart';

class LibraryBackupScreen extends StatefulWidget {
  const LibraryBackupScreen({super.key, required this.library});

  final ScoreLibrary library;

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

  Future<String?> _export() async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final zip = await widget.library.createBackup();
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
    if (source == null) return null;
    final result = await widget.library.restoreBackup(source);
    return 'Restored ${result.scores} scores and ${result.setlists} setlists.';
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
            const Text(
              'A backup includes your PDFs, annotations, setlists, and saved reading positions.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _operation == null
                  ? () => _run('Create backup', _export)
                  : null,
              icon: const Icon(Icons.save_alt),
              label: const Text('Create backup'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _operation == null
                  ? () => _run('Restore backup', _restore)
                  : null,
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('Restore backup'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Restore adds copies to your library and preserves existing items.',
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
