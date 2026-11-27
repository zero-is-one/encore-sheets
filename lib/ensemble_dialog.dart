import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'ensemble_session.dart';

enum EnsembleFollowMode {
  pages('Page turns'),
  scores('Score changes'),
  both('Scores and page turns'),
  facing('Right page of a two-device spread');

  const EnsembleFollowMode(this.label);
  final String label;
}

class EnsembleDialog extends StatefulWidget {
  const EnsembleDialog({
    super.key,
    required this.session,
    required this.lead,
    required this.follow,
    required this.leadingSpread,
    required this.setLeadingSpread,
  });

  final EnsembleSession session;
  final Future<void> Function() lead;
  final Future<void> Function(String, String, EnsembleFollowMode) follow;
  final bool Function() leadingSpread;
  final ValueChanged<bool> setLeadingSpread;

  @override
  State<EnsembleDialog> createState() => _EnsembleDialogState();
}

class _EnsembleDialogState extends State<EnsembleDialog> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  EnsembleFollowMode _mode = EnsembleFollowMode.both;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FormatException catch (error) {
      _error = error.message;
    } catch (_) {
      _error =
          'Could not connect. Check the address, code, and local Wi-Fi access.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Ensemble sync'),
        scrollable: true,
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error case final error?) Text(error),
              if (session.leading || session.following) ...[
                Text(session.leading ? 'Leading' : 'Following'),
                SelectableText(session.address ?? ''),
                if (session.leading)
                  SelectableText('Group code ${session.code}'),
                if (session.leading)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: '${session.address}\n${session.code}',
                              ),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Connection details copied.'),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy connection details'),
                  ),
                if (session.leading)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show left pages of a two-device spread'),
                    value: widget.leadingSpread(),
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() => widget.setLeadingSpread(value));
                          },
                  ),
              ] else ...[
                const Text(
                  'Connect both devices to the same Wi-Fi network. Load a copy of the score on each device.',
                ),
                TextButton(
                  onPressed: _busy ? null : () => _run(widget.lead),
                  child: const Text('Lead a session'),
                ),
                TextField(
                  controller: _address,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Leader address',
                    hintText: '192.168.1.23:12345',
                  ),
                ),
                TextField(
                  controller: _code,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Group code'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final clipboard = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          if (!mounted) return;
                          final lines = clipboard?.text?.trim().split(
                            RegExp(r'\r?\n'),
                          );
                          if (lines == null ||
                              lines.length != 2 ||
                              lines.any((line) => line.trim().isEmpty)) {
                            setState(
                              () => _error = 'Copy the address and code from the leader first.',
                            );
                            return;
                          }
                          setState(() {
                            _error = null;
                            _address.text = lines.first.trim();
                            _code.text = lines.last.trim();
                          });
                        },
                  child: const Text('Paste connection details'),
                ),
                DropdownButton<EnsembleFollowMode>(
                  value: _mode,
                  items: [
                    for (final mode in EnsembleFollowMode.values)
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                  ],
                  onChanged: _busy
                      ? null
                      : (mode) => setState(() => _mode = mode!),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => widget.follow(_address.text, _code.text, _mode),
                        ),
                  child: const Text('Join session'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (session.leading || session.following)
            TextButton(
              onPressed: _busy ? null : () => _run(session.close),
              child: Text(session.leading ? 'End session' : 'Leave session'),
            ),
          FilledButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
