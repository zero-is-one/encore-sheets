import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'score_audio.dart';
import 'score_library.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.library});
  final ScoreLibrary library;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  static final _issues = Uri.https(
    'github.com',
    '/zero-is-one/encoresheets/issues',
  );
  late final _version = _readVersion();

  Future<String> _readVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    } catch (_) {
      return 'Unavailable';
    }
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Diagnostics copied.')));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not copy diagnostics.')),
        );
    }
  }

  Future<void> _openIssues() async {
    try {
      if (await launchUrl(_issues, mode: LaunchMode.externalApplication))
        return;
    } catch (_) {
      // The tracker remains selectable if a browser is unavailable.
    }
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the issue tracker.')),
      );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help and diagnostics')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ExpansionTile(
            title: Text('Import and organize scores'),
            childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              Text(
                'Open the score library to import PDFs, create setlists, and make backups. '
                'Hold a library score’s drag handle to drop it on a setlist or pin it as a tab.',
              ),
            ],
          ),
          const ExpansionTile(
            title: Text('Read and rehearse'),
            childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              Text(
                'Tap the outer edge of a page, use the reader arrows, or pair a pedal '
                'to turn pages. Open Reader tools for linked audio, the metronome, '
                'shortcuts, and ensemble sync.',
              ),
            ],
          ),
          const ExpansionTile(
            title: Text('Transfer or back up a library'),
            childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              Text(
                'Use Backup & restore to copy your catalogue and PDFs. '
                'Save the backup outside this app so it is available if you reinstall.',
              ),
            ],
          ),
          const Divider(),
          FutureBuilder<String>(
            future: _version,
            builder: (context, status) {
              final diagnostics = <String, String>{
                'Version': status.data ?? 'Loading',
                'Platform': kIsWeb ? 'Web' : defaultTargetPlatform.name,
                'Storage': widget.library.storage.persistent
                    ? 'Persistent'
                    : 'Session only',
                'Scores': '${widget.library.recent.length}',
                'Setlists': '${widget.library.setlists.length}',
                'Linked audio': ScoreAudioSession.supported
                    ? 'Available'
                    : 'Unavailable',
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in diagnostics.entries)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(row.key),
                      trailing: Text(row.value),
                    ),
                  TextButton.icon(
                    onPressed: status.connectionState == ConnectionState.done
                        ? () => _copy(
                            diagnostics.entries
                                .map((row) => '${row.key}: ${row.value}')
                                .join('\n'),
                          )
                        : null,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy diagnostics'),
                  ),
                ],
              );
            },
          ),
          TextButton.icon(
            onPressed: _openIssues,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open issue tracker'),
          ),
          SelectableText(_issues.toString()),
        ],
      ),
    ),
  );
}
